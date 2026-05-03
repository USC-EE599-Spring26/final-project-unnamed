//
//  NotificationViewModel.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import Foundation
import os.log
import ParseSwift

@MainActor
class NotificationViewModel: ObservableObject {

    // MARK: - Display model

    struct NotificationItem: Identifiable {
        let id: String                              // AppNotification.objectId
        let type: AppNotification.NotificationType?
        let message: String
        let fromUsername: String
        let relatedId: String
        let createdAt: Date?
        var isRead: Bool
        var result: AppNotification.NotificationResult?
    }

    // MARK: - Published

    @Published var notifications: [NotificationItem] = []
    @Published var isLoading     = false
    @Published var errorMessage: String?

    // MARK: - Derived

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    // MARK: - Fetch

    func fetchNotifications() async {
        guard let currentUser = try? await User.current(),
              let myObjectId  = currentUser.objectId else {
            notifications = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        let raw = (try? await AppNotification
            .query("toUserObjectId" == myObjectId)
            .order([.descending("createdAt")])
            .find()) ?? []

        notifications = raw.compactMap { notif -> NotificationItem? in
            guard let objId    = notif.objectId,
                  let message  = notif.message,
                  let relatedId = notif.relatedId,
                  let from     = notif.fromUsername else { return nil }
            return NotificationItem(
                id: objId,
                type: notif.type,
                message: message,
                fromUsername: from,
                relatedId: relatedId,
                createdAt: notif.createdAt,
                isRead: notif.isRead ?? false,
                result: notif.result
            )
        }
    }

    // MARK: - Accept

    func accept(_ item: NotificationItem) async {
        do {
            switch item.type {
            case .connectionRequest:
                try await Relationship.acceptRequest(objectId: item.relatedId)
                await addClinicianContactIfNeeded(username: item.fromUsername)

            case .carePlanAssignment:
                var assignment = CarePlanAssignment()
                assignment.objectId = item.relatedId
                var fetched  = try await assignment.fetch()
                fetched.status = CarePlanAssignment.statusAccepted
                _ = try await fetched.save()
                await copyCarePlanToPatientStore(from: fetched)

            case .none:
                break
            }
            await markRead(item, result: .accepted)
        } catch {
            errorMessage = "Could not accept: \(error.localizedDescription)"
        }
    }

    // MARK: - Reject

    func reject(_ item: NotificationItem) async {
        do {
            switch item.type {
            case .connectionRequest:
                try await Relationship.rejectRequest(objectId: item.relatedId)

            case .carePlanAssignment:
                var assignment = CarePlanAssignment()
                assignment.objectId = item.relatedId
                var fetched  = try await assignment.fetch()
                fetched.status = CarePlanAssignment.statusRejected
                _ = try await fetched.save()

            case .none:
                break
            }
            await markRead(item, result: .rejected)
        } catch {
            errorMessage = "Could not reject: \(error.localizedDescription)"
        }
    }

    // MARK: - Copy care plan to patient's store

    private func copyCarePlanToPatientStore(from assignment: CarePlanAssignment) async {
        guard let store   = AppDelegateKey.defaultValue?.store,
              let payload = assignment.payload else {
            Logger.contact.warning("copyCarePlanToPatientStore: no payload — skipping")
            return
        }

        do {
            let snapshot = try CarePlanSnapshot.from(jsonString: payload)
            let patientUUID = (try? await store
                .fetchPatients(query: OCKPatientQuery(for: Date())))?.first?.uuid

            var planQuery = OCKCarePlanQuery(for: Date())
            planQuery.ids = [snapshot.carePlanId]
            let existingPlan = (try? await store.fetchCarePlans(query: planQuery))?.first

            let titleForLog = snapshot.carePlanTitle ?? snapshot.carePlanId

            let carePlan: OCKCarePlan
            if let existing = existingPlan {
                carePlan = existing
                Logger.contact.info("copyCarePlan: plan '\(snapshot.carePlanId)' already exists")
            } else {
                let newPlan = OCKCarePlan(
                    id: snapshot.carePlanId,
                    title: snapshot.carePlanTitle ?? snapshot.carePlanId,
                    patientUUID: patientUUID
                )
                carePlan = try await store.addCarePlan(newPlan)
                Logger.contact.info("copyCarePlan: created plan '\(titleForLog)'")
            }

            let taskIds = snapshot.tasks.map { $0.id }
            var taskQuery = OCKTaskQuery(for: Date())
            taskQuery.ids = taskIds
            let existingTaskIds = Set(
                ((try? await store.fetchTasks(query: taskQuery)) ?? []).map { $0.id }
            )

            let tasksToAdd = snapshot.tasks
                .filter { !existingTaskIds.contains($0.id) }
                .map { $0.toOCKTask(carePlanUUID: carePlan.uuid) }

            if !tasksToAdd.isEmpty {
                _ = try await store.addTasks(tasksToAdd)
                Logger.contact.info(
                    "copyCarePlan: added \(tasksToAdd.count) task(s) for '\(titleForLog)'"
                )
            }
        } catch {
            Logger.contact.warning("copyCarePlanToPatientStore failed: \(error)")
        }
    }

    // MARK: - Auto-add clinician contact

    private func addClinicianContactIfNeeded(username: String) async {
        guard let store = AppDelegateKey.defaultValue?.store else { return }

        let contactId = "clinician-\(username)"

        var query = OCKContactQuery()
        query.ids = [contactId]
        let existing = (try? await store.fetchContacts(query: query)) ?? []
        guard existing.isEmpty else {
            Logger.contact.info("Clinician contact '\(contactId)' already exists — skipping.")
            return
        }

        var name = PersonNameComponents()
        name.givenName = username.capitalized

        var contact = OCKContact(id: contactId, name: name, carePlanUUID: nil)
        contact.title = "Dr."
        contact.role  = "Care Team"

        do {
            _ = try await store.addContact(contact)
            Logger.contact.info("Added clinician contact: \(contactId)")
        } catch {
            Logger.contact.warning("Failed to add clinician contact: \(error)")
        }
    }

    // MARK: - Mark read

    func markRead(_ item: NotificationItem, result: AppNotification.NotificationResult? = nil) async {
        do {
            var found = try await AppNotification
                .query("objectId" == item.id)
                .first()
            found.isRead = true
            if let result { found.result = result }
            _ = try await found.save()

            notifications = notifications.map { notification in
                guard notification.id == item.id else { return notification }
                var updated = notification
                updated.isRead = true
                updated.result = result
                return updated
            }
        } catch {
            errorMessage = "Could not update notification: \(error.localizedDescription)"
            Logger.contact.warning("NotificationViewModel: markRead failed: \(error)")
        }
    }
}
