//
//  PatientDetailViewModel.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import Foundation
import ParseSwift
import os.log

@MainActor
class PatientDetailViewModel: ObservableObject {

    // MARK: - Care plan display model

    struct CarePlanItem: Identifiable {
        let id: String          // OCKCarePlan.id
        let title: String
        /// nil  = not assigned yet
        /// non-nil = "pending" | "accepted" | "rejected"
        var assignmentStatus: String?
        var assignmentObjectId: String?
    }

    // MARK: - Published

    @Published var carePlans: [CarePlanItem] = []
    @Published var isLoading     = false
    @Published var errorMessage: String?

    // MARK: - Private

    let patient: PatientManagementViewModel.PatientRow

    init(patient: PatientManagementViewModel.PatientRow) {
        self.patient = patient
    }

    // MARK: - Fetch

    func fetchCarePlans() async {
        guard let store = AppDelegateKey.defaultValue?.store else { return }
        isLoading = true
        defer { isLoading = false }

        guard let currentUser = try? await User.current(),
              let myObjectId = currentUser.objectId else { return }

        // 1. Existing CarePlanAssignment records for this (clinician, patient) pair
        let assignments = (try? await CarePlanAssignment
            .query(
                "clinicianObjectId" == myObjectId,
                "patientObjectId"   == patient.patientObjectId
            )
            .find()) ?? []

        let assignmentMap = Dictionary(
            uniqueKeysWithValues: assignments.compactMap { assignment -> (String, CarePlanAssignment)? in
                guard let cpId = assignment.carePlanId else { return nil }
                return (cpId, assignment)
            }
        )

        // 2. Clinician's own care plans from local CareKit store
        let query = OCKCarePlanQuery(for: Date())
        let plans = (try? await store.fetchCarePlans(query: query)) ?? []

        carePlans = plans.map { plan in
            let existing = assignmentMap[plan.id]
            return CarePlanItem(
                id: plan.id,
                title: plan.title,
                assignmentStatus: existing?.status,
                assignmentObjectId: existing?.objectId
            )
        }
    }

    // MARK: - Assign / Unassign

    func toggleAssignment(for item: CarePlanItem) async {
        do {
            let currentUser = try await User.current()
            guard let myObjectId = currentUser.objectId,
                  let myUsername = currentUser.username else {
                errorMessage = "Could not determine current user."
                return
            }

            if let existingId = item.assignmentObjectId,
               let existingStatus = item.assignmentStatus {

                if existingStatus == CarePlanAssignment.statusAccepted
                    || existingStatus == CarePlanAssignment.statusPending {
                    // Revoke: mark as rejected
                    var assignment = CarePlanAssignment()
                    assignment.objectId = existingId
                    var fetched = try await assignment.fetch()
                    fetched.status = CarePlanAssignment.statusRejected
                    _ = try await fetched.save()

                    updateLocalItem(id: item.id, status: CarePlanAssignment.statusRejected,
                                    objId: existingId)
                } else {
                    // Re-assign (was rejected): flip back to pending
                    var assignment = CarePlanAssignment()
                    assignment.objectId = existingId
                    var fetched = try await assignment.fetch()
                    fetched.status = CarePlanAssignment.statusPending
                    _ = try await fetched.save()

                    // Re-notify patient
                    try await AppNotification.send(
                        toUserObjectId: patient.patientObjectId,
                        fromUserObjectId: myObjectId,
                        fromUsername: myUsername,
                        type: AppNotification.typeCarePlanAssignment,
                        relatedId: existingId,
                        message: "\(myUsername.capitalized) assigned care plan: \(item.title)"
                    )
                    updateLocalItem(id: item.id, status: CarePlanAssignment.statusPending,
                                    objId: existingId)
                }

            } else {
                // First-time assignment
                let saved = try await CarePlanAssignment.create(
                    clinicianObjectId: myObjectId,
                    clinicianUsername: myUsername,
                    patientObjectId: patient.patientObjectId,
                    patientUsername: patient.username,
                    carePlanId: item.id,
                    carePlanTitle: item.title
                )
                guard let assignment = saved, let objId = assignment.objectId else {
                    errorMessage = "Assignment already exists."
                    return
                }

                try await AppNotification.send(
                    toUserObjectId: patient.patientObjectId,
                    fromUserObjectId: myObjectId,
                    fromUsername: myUsername,
                    type: AppNotification.typeCarePlanAssignment,
                    relatedId: objId,
                    message: "\(myUsername.capitalized) assigned care plan: \(item.title)"
                )
                updateLocalItem(id: item.id, status: CarePlanAssignment.statusPending,
                                objId: objId)
            }
        } catch {
            errorMessage = "Could not update assignment: \(error.localizedDescription)"
        }
    }

    // MARK: - Private helpers

    private func updateLocalItem(id: String, status: String, objId: String) {
        carePlans = carePlans.map { item in
            guard item.id == id else { return item }
            return CarePlanItem(
                id: item.id,
                title: item.title,
                assignmentStatus: status,
                assignmentObjectId: objId
            )
        }
    }
}
