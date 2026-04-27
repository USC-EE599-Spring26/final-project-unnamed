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
        let id: String                  // AppNotification.objectId
        let type: String                // typeConnectionRequest | typeCarePlanAssignment
        let message: String
        let fromUsername: String
        let relatedId: String
        let createdAt: Date?
        var isRead: Bool
        /// "accepted" | "rejected" | nil (still pending)
        var result: String?
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
                  let type     = notif.type,
                  let message  = notif.message,
                  let relatedId = notif.relatedId,
                  let from     = notif.fromUsername else { return nil }
            return NotificationItem(
                id: objId,
                type: type,
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
            case AppNotification.typeConnectionRequest:
                // Claims patientObjectId (if not yet set), tightens ACL, sets accepted.
                try await Relationship.acceptRequest(objectId: item.relatedId)
                // Auto-add the clinician to the patient's local contact list.
                await addClinicianContactIfNeeded(username: item.fromUsername)

            case AppNotification.typeCarePlanAssignment:
                var assignment = CarePlanAssignment()
                assignment.objectId = item.relatedId
                var fetched  = try await assignment.fetch()
                fetched.status = CarePlanAssignment.statusAccepted
                _ = try await fetched.save()

            default:
                break
            }
            await markRead(item, result: AppNotification.resultAccepted)
        } catch {
            errorMessage = "Could not accept: \(error.localizedDescription)"
        }
    }

    // MARK: - Reject

    func reject(_ item: NotificationItem) async {
        do {
            switch item.type {
            case AppNotification.typeConnectionRequest:
                // Claims patientObjectId (if not yet set), tightens ACL, sets rejected.
                try await Relationship.rejectRequest(objectId: item.relatedId)

            case AppNotification.typeCarePlanAssignment:
                var assignment = CarePlanAssignment()
                assignment.objectId = item.relatedId
                var fetched  = try await assignment.fetch()
                fetched.status = CarePlanAssignment.statusRejected
                _ = try await fetched.save()

            default:
                break
            }
            await markRead(item, result: AppNotification.resultRejected)
        } catch {
            errorMessage = "Could not reject: \(error.localizedDescription)"
        }
    }

    // MARK: - Auto-add clinician contact

    /// Adds the clinician as an OCKContact in the patient's local CareKit store
    /// after they accept a connection request. Checks for an existing contact first
    /// so repeated accepts (or re-logins) don't create duplicates.
    private func addClinicianContactIfNeeded(username: String) async {
        guard let store = AppDelegateKey.defaultValue?.store else { return }

        let contactId = "clinician-\(username)"

        // Existence check — skip if already in the local store.
        var query = OCKContactQuery()
        query.ids = [contactId]
        let existing = (try? await store.fetchContacts(query: query)) ?? []
        guard existing.isEmpty else {
            Logger.contact.info("Clinician contact '\(contactId)' already exists — skipping.")
            return
        }

        // Build a minimal contact from the username we already have.
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

    func markRead(_ item: NotificationItem, result: String? = nil) async {
        do {
            var notif = AppNotification()
            notif.objectId = item.id
            var fetched  = try await notif.fetch()
            fetched.isRead = true
            if let result { fetched.result = result }
            _ = try await fetched.save()

            // Update local state so UI reflects the change immediately.
            notifications = notifications.map { notification in
                guard notification.id == item.id else { return notification }
                var updated = notification
                updated.isRead = true
                updated.result = result
                return updated
            }
        } catch {
            Logger.contact.warning("NotificationViewModel: markRead failed: \(error)")
        }
    }
}
