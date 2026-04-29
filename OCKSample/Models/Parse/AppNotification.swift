//
//  AppNotification.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import Foundation
import os.log
import ParseSwift

struct AppNotification: ParseObject {

    // MARK: - Nested enums

    enum NotificationType: String, Codable, CaseIterable, Identifiable {
        var id: Self { self }
        case connectionRequest  = "connection_request"
        case carePlanAssignment = "careplan_assignment"
    }

    enum NotificationResult: String, Codable, CaseIterable, Identifiable {
        var id: Self { self }
        case accepted
        case rejected
    }

    // MARK: - ParseObject required

    var objectId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var ACL: ParseACL?
    var originalData: Data?

    // MARK: - Fields

    var toUserObjectId: String?
    var fromUserObjectId: String?
    var fromUsername: String?

    var type: NotificationType?
    var relatedId: String?
    var message: String?
    var isRead: Bool?

    var result: NotificationResult?
}

// MARK: - Merge

extension AppNotification {
    func merge(with object: Self) throws -> Self {
        var updated = try mergeParse(with: object)
        if updated.shouldRestoreKey(\.toUserObjectId, original: object) {
            updated.toUserObjectId = object.toUserObjectId
        }
        if updated.shouldRestoreKey(\.fromUserObjectId, original: object) {
            updated.fromUserObjectId = object.fromUserObjectId
        }
        if updated.shouldRestoreKey(\.fromUsername, original: object) {
            updated.fromUsername = object.fromUsername
        }
        if updated.shouldRestoreKey(\.type, original: object) {
            updated.type = object.type
        }
        if updated.shouldRestoreKey(\.relatedId, original: object) {
            updated.relatedId = object.relatedId
        }
        if updated.shouldRestoreKey(\.message, original: object) {
            updated.message = object.message
        }
        if updated.shouldRestoreKey(\.isRead, original: object) {
            updated.isRead = object.isRead
        }
        if updated.shouldRestoreKey(\.result, original: object) {
            updated.result = object.result
        }
        return updated
    }
}

// MARK: - Send

extension AppNotification {

    // swiftlint:disable function_parameter_count
    @discardableResult
    static func send(
        toUserObjectId: String,
        fromUserObjectId: String,
        fromUsername: String,
        type: NotificationType,
        relatedId: String,
        message: String
    ) async throws -> AppNotification {
        var notification = AppNotification()
        notification.objectId         = UUID().uuidString  // Required: allowCustomObjectId: true
        notification.toUserObjectId   = toUserObjectId
        notification.fromUserObjectId = fromUserObjectId
        notification.fromUsername     = fromUsername
        notification.type             = type
        notification.relatedId        = relatedId
        notification.message          = message
        notification.isRead           = false

        var acl = ParseACL()
        acl.setReadAccess(objectId: fromUserObjectId, value: true)
        acl.setReadAccess(objectId: toUserObjectId, value: true)
        acl.setWriteAccess(objectId: toUserObjectId, value: true)
        notification.ACL = acl

        let saved = try await notification.save()
        Logger.contact.info(
            "AppNotification sent type=\(type.rawValue) to=\(toUserObjectId, privacy: .private)"
        )
        return saved
    }
}
