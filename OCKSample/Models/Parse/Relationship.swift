//
//  Relationship.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//
//  Parse table that tracks clinician-patient connection requests.
//  A row is created by the clinician; the patient accepts or rejects.
//
//  ACL strategy (Option A):
//    • Unlinked row (patientObjectId == nil): publicRead + publicWrite
//      so link-on-login can claim the row without knowing the patient's objectId.
//    • Linked row: clinician read/write + patient read/write, no public access.
//

import Foundation
import os.log
import ParseSwift

struct Relationship: ParseObject {

    // MARK: - Status constants

    static let statusPending  = "pending"
    static let statusAccepted = "accepted"
    static let statusRejected = "rejected"

    // MARK: - ParseObject required

    var objectId: String?
    var createdAt: Date?
    var updatedAt: Date?
    var ACL: ParseACL?
    var originalData: Data?

    // MARK: - Fields

    /// The clinician who initiated the connection request.
    var doctorObjectId: String?
    var doctorUsername: String?

    /// The patient being invited.
    /// Nil until `linkPendingForCurrentUser()` claims the row (link-on-login).
    var patientObjectId: String?
    var patientUsername: String?

    /// Contact identifiers used when the patient hasn't signed up yet.
    var patientEmail: String?
    var patientPhone: String?

    /// "pending" | "accepted" | "rejected"
    var status: String?
}

// MARK: - Merge

extension Relationship {
    func merge(with object: Self) throws -> Self {
        var updated = try mergeParse(with: object)
        if updated.shouldRestoreKey(\.doctorObjectId, original: object) {
            updated.doctorObjectId = object.doctorObjectId
        }
        if updated.shouldRestoreKey(\.doctorUsername, original: object) {
            updated.doctorUsername = object.doctorUsername
        }
        if updated.shouldRestoreKey(\.patientObjectId, original: object) {
            updated.patientObjectId = object.patientObjectId
        }
        if updated.shouldRestoreKey(\.patientUsername, original: object) {
            updated.patientUsername = object.patientUsername
        }
        if updated.shouldRestoreKey(\.patientEmail, original: object) {
            updated.patientEmail = object.patientEmail
        }
        if updated.shouldRestoreKey(\.patientPhone, original: object) {
            updated.patientPhone = object.patientPhone
        }
        if updated.shouldRestoreKey(\.status, original: object) {
            updated.status = object.status
        }
        return updated
    }
}

// MARK: - ACL helper

extension Relationship {
    /// Tightened ACL once the patient's objectId is known.
    static func makeACL(clinicianObjectId: String, patientObjectId: String) -> ParseACL {
        var acl = ParseACL()
        acl.setReadAccess(objectId: clinicianObjectId, value: true)
        acl.setWriteAccess(objectId: clinicianObjectId, value: true)
        acl.setReadAccess(objectId: patientObjectId, value: true)
        acl.setWriteAccess(objectId: patientObjectId, value: true)
        return acl
    }
}

// MARK: - Create request

extension Relationship {
    /// Creates a pending connection-request row.
    /// Identified by email only — phone is no longer used as an identifier.
    ///
    /// ACL strategy:
    ///   • Always publicRead + publicWrite so the patient can claim the row on login.
    ///   • `acceptRequest()` tightens the ACL once the patient's objectId is known.
    ///
    /// - Returns: The saved row, or `nil` if a duplicate pending row already exists.
    @discardableResult
    static func createRequest(
        clinicianObjectId: String,
        clinicianUsername: String,
        patientUsername: String?,
        patientEmail: String?
    ) async throws -> Relationship? {

        guard let email = patientEmail, !email.isEmpty else {
            Logger.contact.info("Relationship.createRequest: no email — skipped.")
            return nil
        }

        let dupCheck = Relationship.query(
            "doctorObjectId" == clinicianObjectId,
            "patientEmail"   == email,
            "status"         == statusPending
        )
        if (try? await dupCheck.first()) != nil {
            Logger.contact.info("Relationship: duplicate pending row — skipped.")
            return nil
        }

        var rel = Relationship()
        rel.objectId        = UUID().uuidString     // ParseCareKit uses allowCustomObjectId: true
        rel.doctorObjectId  = clinicianObjectId
        rel.doctorUsername  = clinicianUsername
        rel.patientUsername = patientUsername
        rel.patientEmail    = email
        rel.status          = statusPending

        var acl = ParseACL()
        acl.publicRead  = true
        acl.publicWrite = true
        rel.ACL = acl

        let res = try await rel.save()
        return res
    }
}

extension Relationship {
    static func linkPendingForCurrentUser() async {
        guard let user = try? await User.current(),
              let myObjectId = user.objectId,
              let myUsername = user.username,
              let email = user.email, !email.isEmpty else { return }

        let candidates = (try? await Relationship.query(
            "patientEmail" == email,
            "status"       == statusPending
        ).find()) ?? []

        guard !candidates.isEmpty else { return }
        Logger.login.info("Relationship.linkPendingForCurrentUser: \(candidates.count) candidate(s)")

        for rel in candidates {
            guard let relId = rel.objectId else { continue }

            if let existing = rel.patientObjectId, !existing.isEmpty { continue }

            guard rel.doctorObjectId != myObjectId else { continue }

            var updated = rel
            updated.patientObjectId = myObjectId
            updated.patientUsername = myUsername

            if let docId = rel.doctorObjectId {
                updated.ACL = makeACL(clinicianObjectId: docId, patientObjectId: myObjectId)
            }

            do {
                _ = try await updated.save()
                Logger.login.info("Relationship \(relId) linked to \(myUsername, privacy: .private)")

                if let docId = rel.doctorObjectId,
                   let docUsername = rel.doctorUsername {
                    try await AppNotification.send(
                        toUserObjectId: myObjectId,
                        fromUserObjectId: docId,
                        fromUsername: docUsername,
                        type: .connectionRequest,
                        relatedId: relId,
                        message: "Dr. \(docUsername.capitalized) wants to connect with you."
                    )
                }
            } catch {
                Logger.login.warning("Relationship: failed to link row \(relId): \(error)")
            }
        }
    }
}

extension Relationship {
    static func acceptRequest(objectId: String) async throws {
        let currentUser = try await User.current()
        guard let myObjectId = currentUser.objectId,
              let myUsername = currentUser.username else { return }

        var stub = Relationship()
        stub.objectId = objectId
        var row = try await stub.fetch()

        if row.patientObjectId == nil || row.patientObjectId!.isEmpty {  // swiftlint:disable:this force_unwrapping
            row.patientObjectId = myObjectId
            row.patientUsername = myUsername
        }

        row.status = statusAccepted

        // Tighten ACL — both sides get read + write so the clinician
        // can still cancel and the patient can still update later.
        if let docId = row.doctorObjectId {
            row.ACL = makeACL(clinicianObjectId: docId, patientObjectId: myObjectId)
        }

        _ = try await row.save()
        Logger.contact.info("Relationship \(objectId) accepted by \(myUsername, privacy: .private)")
    }

    static func rejectRequest(objectId: String) async throws {
        let currentUser = try await User.current()
        guard let myObjectId = currentUser.objectId else { return }

        var stub = Relationship()
        stub.objectId = objectId
        var row = try await stub.fetch()

        if row.patientObjectId == nil || row.patientObjectId!.isEmpty {  // swiftlint:disable:this force_unwrapping
            row.patientObjectId = myObjectId
        }

        row.status = statusRejected

        // Tighten ACL — don't leave the row publicly writable forever.
        if let docId = row.doctorObjectId {
            row.ACL = makeACL(clinicianObjectId: docId, patientObjectId: myObjectId)
        }

        _ = try await row.save()
        Logger.contact.info("Relationship \(objectId) rejected")
    }
}
