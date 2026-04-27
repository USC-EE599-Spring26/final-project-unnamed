//
//  CarePlanAssignment.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//
//  Parse table tracking which care plans a clinician has assigned to a patient.
//  One row per (clinician, patient, carePlan) triple.
//  ACL: clinician read/write + patient read/write.
//

import Foundation
import os.log
import ParseSwift

struct CarePlanAssignment: ParseObject {

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

    var clinicianObjectId: String?
    var clinicianUsername: String?
    var patientObjectId: String?
    var patientUsername: String?

    /// The OCKCarePlan.id this assignment refers to.
    var carePlanId: String?
    var carePlanTitle: String?

    /// "pending" | "accepted" | "rejected"
    var status: String?

    /// JSON-encoded CarePlanSnapshot — written by the clinician when assigning,
    /// read by the patient when accepting to copy the care plan into their store.
    var payload: String?
}

// MARK: - Merge

extension CarePlanAssignment {
    func merge(with object: Self) throws -> Self {
        var updated = try mergeParse(with: object)
        if updated.shouldRestoreKey(\.clinicianObjectId, original: object) {
            updated.clinicianObjectId = object.clinicianObjectId
        }
        if updated.shouldRestoreKey(\.clinicianUsername, original: object) {
            updated.clinicianUsername = object.clinicianUsername
        }
        if updated.shouldRestoreKey(\.patientObjectId, original: object) {
            updated.patientObjectId = object.patientObjectId
        }
        if updated.shouldRestoreKey(\.patientUsername, original: object) {
            updated.patientUsername = object.patientUsername
        }
        if updated.shouldRestoreKey(\.carePlanId, original: object) {
            updated.carePlanId = object.carePlanId
        }
        if updated.shouldRestoreKey(\.carePlanTitle, original: object) {
            updated.carePlanTitle = object.carePlanTitle
        }
        if updated.shouldRestoreKey(\.status, original: object) {
            updated.status = object.status
        }
        if updated.shouldRestoreKey(\.payload, original: object) {
            updated.payload = object.payload
        }
        return updated
    }
}

// MARK: - Create helper

extension CarePlanAssignment {

    // swiftlint:disable function_parameter_count
    @discardableResult
    static func create(
        clinicianObjectId: String,
        clinicianUsername: String,
        patientObjectId: String,
        patientUsername: String,
        carePlanId: String,
        carePlanTitle: String,
        payload: String? = nil
    ) async throws -> CarePlanAssignment? {

        // Idempotency: don't duplicate for the same (clinician, patient, carePlan) triple.
        let existing = try? await CarePlanAssignment.query(
            "clinicianObjectId" == clinicianObjectId,
            "patientObjectId"   == patientObjectId,
            "carePlanId"        == carePlanId
        ).first()

        if existing != nil {
            Logger.contact.info("CarePlanAssignment: duplicate row — skipped.")
            return nil
        }

        var assignment = CarePlanAssignment()
        assignment.objectId          = UUID().uuidString   // Required: allowCustomObjectId: true
        assignment.clinicianObjectId = clinicianObjectId
        assignment.clinicianUsername = clinicianUsername
        assignment.patientObjectId   = patientObjectId
        assignment.patientUsername   = patientUsername
        assignment.carePlanId        = carePlanId
        assignment.carePlanTitle     = carePlanTitle
        assignment.status            = statusPending
        assignment.payload           = payload

        // Clinician read/write + patient read/write.
        var acl = ParseACL()
        acl.setReadAccess(objectId: clinicianObjectId, value: true)
        acl.setWriteAccess(objectId: clinicianObjectId, value: true)
        acl.setReadAccess(objectId: patientObjectId, value: true)
        acl.setWriteAccess(objectId: patientObjectId, value: true)
        assignment.ACL = acl

        return try await assignment.save()
    }
}
