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
    @Published var isLoading      = false
    @Published var isProcessing   = false   // true while toggleAssignment is in-flight
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
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
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
                    // Re-assign (was rejected): rebuild snapshot in case plan changed
                    let payload = await buildSnapshot(for: item)
                    var assignment = CarePlanAssignment()
                    assignment.objectId = existingId
                    var fetched = try await assignment.fetch()
                    fetched.status  = CarePlanAssignment.statusPending
                    fetched.payload = payload
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
                // First-time assignment — build snapshot of the care plan + tasks
                let payload = await buildSnapshot(for: item)
                let saved = try await CarePlanAssignment.create(
                    clinicianObjectId: myObjectId,
                    clinicianUsername: myUsername,
                    patientObjectId: patient.patientObjectId,
                    patientUsername: patient.username,
                    carePlanId: item.id,
                    carePlanTitle: item.title,
                    payload: payload
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
                    message: "\(myUsername.capitalized) assigned you a care plan: \(item.title)"
                )
                updateLocalItem(id: item.id, status: CarePlanAssignment.statusPending,
                                objId: objId)
            }
        } catch {
            errorMessage = "Could not update assignment: \(error.localizedDescription)"
        }
    }

    // MARK: - Private helpers

    /// Serialises the care plan and all its tasks into a JSON string for storage
    /// in CarePlanAssignment.payload. Returns nil if the store is unavailable or
    /// the plan cannot be found (assignment still works — patient just won't get tasks).
    private func buildSnapshot(for item: CarePlanItem) async -> String? {
        guard let store = AppDelegateKey.defaultValue?.store else { return nil }

        // Fetch the full OCKCarePlan so we have its UUID.
        var planQuery = OCKCarePlanQuery(for: Date())
        planQuery.ids = [item.id]
        guard let plan = (try? await store.fetchCarePlans(query: planQuery))?.first else {
            Logger.contact.warning("buildSnapshot: care plan '\(item.id)' not found")
            return nil
        }

        // Fetch all tasks that belong to this care plan.
        var taskQuery = OCKTaskQuery(for: Date())
        taskQuery.carePlanUUIDs = [plan.uuid]
        let tasks = (try? await store.fetchTasks(query: taskQuery)) ?? []

        let snapshot = CarePlanSnapshot(plan: plan, tasks: tasks)
        let json = try? snapshot.toJSONString()
        Logger.contact.info(
            "buildSnapshot: '\(item.title)' — \(tasks.count) task(s) serialised"
        )
        return json
    }

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
