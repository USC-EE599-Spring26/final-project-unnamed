//
//  NotificationViewModel.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

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
    }

    // MARK: - Published

    @Published var notifications: [NotificationItem] = []
    @Published var isLoading     = false
    @Published var errorMessage: String?

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
                isRead: notif.isRead ?? false
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

            case AppNotification.typeCarePlanAssignment:
                var assignment = CarePlanAssignment()
                assignment.objectId = item.relatedId
                var fetched  = try await assignment.fetch()
                fetched.status = CarePlanAssignment.statusAccepted
                _ = try await fetched.save()

            default:
                break
            }
            await markRead(item)
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
            await markRead(item)
        } catch {
            errorMessage = "Could not reject: \(error.localizedDescription)"
        }
    }

    // MARK: - Mark read

    func markRead(_ item: NotificationItem) async {
        do {
            var notif = AppNotification()
            notif.objectId = item.id
            var fetched  = try await notif.fetch()
            fetched.isRead = true
            _ = try await fetched.save()

            // Update local state.
            notifications = notifications.map { notification in
                guard notification.id == item.id else { return notification }
                var updated = notification
                updated.isRead = true
                return updated
            }
        } catch {
            Logger.contact.warning("NotificationViewModel: markRead failed: \(error)")
        }
    }
}
