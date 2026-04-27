//
//  Clinician.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//
//  Per-clinician Parse table.
//  Stores the list of patient usernames this clinician has linked.
//  ACL: owner read/write only (private data).
//

import Foundation
import os.log
import ParseSwift

struct Clinician: ParseObject {
    var objectId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var ACL: ParseACL?
    var originalData: Data?

    var username: String?
    var patientUsernames: [String]?
}

// MARK: - Merge

extension Clinician {
    func merge(with object: Self) throws -> Self {
        var updated = try mergeParse(with: object)
        if updated.shouldRestoreKey(\.username, original: object) {
            updated.username = object.username
        }
        if updated.shouldRestoreKey(\.patientUsernames, original: object) {
            updated.patientUsernames = object.patientUsernames
        }
        return updated
    }
}

// MARK: - Upsert helper

extension Clinician {
    /// Creates or updates the `Clinician` row for the currently logged-in user.
    /// Call once after clinician signup to establish the record.
    static func upsertForCurrentUser() async {
        guard let currentUser = try? await User.current(),
              let username = currentUser.username else { return }

        let existing = try? await Clinician.query("username" == username).first()
        var entry = existing ?? Clinician()

        entry.username = username
        // Preserve existing patient list; only initialise if brand new record
        if entry.patientUsernames == nil {
            entry.patientUsernames = []
        }

        // Owner-only access — clinician's patient list is private
        var acl = ParseACL()
        if let oid = currentUser.objectId {
            acl.setReadAccess(objectId: oid, value: true)
            acl.setWriteAccess(objectId: oid, value: true)
        }
        entry.ACL = acl

        do {
            _ = try await entry.save()
            Logger.login.info("Clinician entry saved for \(username, privacy: .private)")
        } catch {
            Logger.login.warning("Could not save Clinician entry: \(error)")
        }
    }

    /// Fetches the `Clinician` row for the currently logged-in user.
    /// Returns `nil` if no record exists yet.
    static func fetchForCurrentUser() async throws -> Clinician? {
        guard let username = try? await User.current().username else { return nil }
        return try? await Clinician.query("username" == username).first()
    }
}
