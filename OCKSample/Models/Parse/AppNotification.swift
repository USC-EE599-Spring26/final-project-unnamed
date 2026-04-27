//
//  AppNotification.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//
//  Parse table for in-app notifications (connection requests, care plan assignments).
//
//  ACL: sender read, recipient read+write (so recipient can mark isRead / act on it).
//

import Foundation
import os.log
import ParseSwift

struct AppNotification: ParseObject {

    // MARK: - Type constants

    static let typeConnectionRequest  = "connection_request"
    static let typeCarePlanAssignment = "careplan_assignment"

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

    /// "connection_request" | "careplan_assignment"
    var type: String?

    /// objectId of the related Relationship or CarePlanAssignment row.
    var relatedId: String?

    /// Human-readable notification body shown in the UI.
    var message: String?

    /// Recipient sets this to true once they have seen the notification.
    var isRead: Bool?
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
        return updated
    }
}

// MARK: - Send helper

extension AppNotification {

    // swiftlint:disable function_parameter_count
    @discardableResult
    static func send(
        toUserObjectId: String,
        fromUserObjectId: String,
        fromUsername: String,
        type: String,
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

        // Sender can read; recipient can read + write (to mark isRead and act on it).
        var acl = ParseACL()
        acl.setReadAccess(objectId: fromUserObjectId, value: true)
        acl.setReadAccess(objectId: toUserObjectId, value: true)
        acl.setWriteAccess(objectId: toUserObjectId, value: true)
        notification.ACL = acl

        let saved = try await notification.save()
        Logger.contact.info(
            "AppNotification sent type=\(type) to=\(toUserObjectId, privacy: .private)"
        )
        return saved
    }
}
