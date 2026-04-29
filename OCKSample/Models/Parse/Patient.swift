//
//  Patient.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//
//  Public-read Parse table that stores patient profile data.
//  Written at signup so clinicians can search by username.
//  ACL: publicRead = true, owner write.
//

import Foundation
import os.log
import ParseSwift

struct Patient: ParseObject {
    var objectId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var ACL: ParseACL?
    var originalData: Data?

    var username: String?
    var email: String?
    var phoneNumber: String?
}

// MARK: - Merge

extension Patient {
    func merge(with object: Self) throws -> Self {
        var updated = try mergeParse(with: object)
        if updated.shouldRestoreKey(\.username, original: object) {
            updated.username = object.username
        }
        if updated.shouldRestoreKey(\.email, original: object) {
            updated.email = object.email
        }
        if updated.shouldRestoreKey(\.phoneNumber, original: object) {
            updated.phoneNumber = object.phoneNumber
        }
        return updated
    }
}

// MARK: - Upsert helper

extension Patient {
    /// Creates or updates the `Patient` row for the currently logged-in user.
    /// Call once after patient signup so clinicians can find this account.
    static func upsertForCurrentUser() async {
        guard let currentUser = try? await User.current(),
              let username = currentUser.username else { return }

        let existing = try? await Patient.query("username" == username).first()
        var entry = existing ?? Patient()

        entry.username    = username
        entry.email       = currentUser.email

        // Public read so any authenticated clinician can search; only owner can write
        var acl = ParseACL()
        acl.publicRead = true
        if let oid = currentUser.objectId {
            acl.setWriteAccess(objectId: oid, value: true)
        }
        entry.ACL = acl

        do {
            _ = try await entry.save()
            Logger.login.info("Patient entry saved for \(username, privacy: .private)")
        } catch {
            Logger.login.warning("Could not save Patient entry: \(error)")
        }
    }
}
