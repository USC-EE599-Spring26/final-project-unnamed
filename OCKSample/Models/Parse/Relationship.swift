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

        // Require at least one identifier.
        guard let email = patientEmail, !email.isEmpty else {
            Logger.contact.info("Relationship.createRequest: no email — skipped.")
            return nil
        }

        // Idempotency: don't create a duplicate pending row for the same email.
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

        // Always publicRead + publicWrite.
        // The patient claims the row in acceptRequest() and tightens the ACL then.
        var acl = ParseACL()
        acl.publicRead  = true
        acl.publicWrite = true
        rel.ACL = acl

        Logger.contact.info("Relationship.createRequest: saving for \(email, privacy: .private)")
        Logger.contact.info("""
        rel dump:
          doctorObjectId:  \(rel.doctorObjectId ?? "nil", privacy: .public)
          doctorUsername:  \(rel.doctorUsername ?? "nil", privacy: .public)
          patientObjectId: \(rel.patientObjectId ?? "nil", privacy: .public)
          patientUsername: \(rel.patientUsername ?? "nil", privacy: .public)
          patientEmail:    \(rel.patientEmail ?? "nil", privacy: .public)
          patientPhone:    \(rel.patientPhone ?? "nil", privacy: .public)
          status:          \(rel.status ?? "nil", privacy: .public)
          objectId:        \(rel.objectId ?? "nil", privacy: .public)
          ACL:             \(String(describing: rel.ACL), privacy: .public)
        """)
        let res = try await rel.save()

        Logger.contact.info("Relationship.createRequest: saved")
        return res
//        return try await rel.save()
    }
}

// MARK: - Link-on-login

extension Relationship {
    /// Runs after every successful login.
    /// Finds pending rows addressed to this user's email, claims each one
    /// by filling in patientObjectId/patientUsername + tightening the ACL,
    /// then dispatches the deferred connection-request notification.
    /// Idempotent — rows that are already linked are skipped.
    static func linkPendingForCurrentUser() async {
        guard let user = try? await User.current(),
              let myObjectId = user.objectId,
              let myUsername = user.username,
              let email = user.email, !email.isEmpty else { return }

        // Match by email only.
        let candidates = (try? await Relationship.query(
            "patientEmail" == email,
            "status"       == statusPending
        ).find()) ?? []

        guard !candidates.isEmpty else { return }
        Logger.login.info("Relationship.linkPendingForCurrentUser: \(candidates.count) candidate(s)")

        for rel in candidates {
            guard let relId = rel.objectId else { continue }

            // Idempotent: skip rows already linked.
            if let existing = rel.patientObjectId, !existing.isEmpty { continue }

            // Safety: don't self-connect.
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

                // Dispatch the deferred notification now that we know the patient.
                if let docId = rel.doctorObjectId,
                   let docUsername = rel.doctorUsername {
                    try await AppNotification.send(
                        toUserObjectId: myObjectId,
                        fromUserObjectId: docId,
                        fromUsername: docUsername,
                        type: AppNotification.typeConnectionRequest,
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

// MARK: - Patient accept / reject

extension Relationship {
    /// Called by the patient to accept a connection request.
    ///
    /// Works in two scenarios:
    ///   1. Row is still unlinked (publicWrite) — claims it and accepts in one save.
    ///   2. Row was already claimed by `linkPendingForCurrentUser` (patient has write) — just flips status.
    ///
    /// In both cases the ACL is tightened to clinician + patient only.
    static func acceptRequest(objectId: String) async throws {
        let currentUser = try await User.current()
        guard let myObjectId = currentUser.objectId,
              let myUsername = currentUser.username else { return }

        var stub = Relationship()
        stub.objectId = objectId
        var row = try await stub.fetch()

        // Claim if not yet linked (public-ACL path).
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

    /// Called by the patient to reject a connection request.
    /// Sets status = rejected and tightens ACL so the row is no longer public.
    static func rejectRequest(objectId: String) async throws {
        let currentUser = try await User.current()
        guard let myObjectId = currentUser.objectId else { return }

        var stub = Relationship()
        stub.objectId = objectId
        var row = try await stub.fetch()

        // Claim objectId so we can set a proper ACL even on rejection.
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
