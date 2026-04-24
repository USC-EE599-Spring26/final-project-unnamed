//
//  CarePlanManagementViewModel.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import Foundation
import os.log

@MainActor
class CarePlanManagementViewModel: ObservableObject {

    @Published var carePlans: [OCKCarePlan] = []
    @Published var error: AppError?

    func fetchCarePlans() async {
        guard let store = AppDelegateKey.defaultValue?.store else { return }
        let query = OCKCarePlanQuery(for: Date())
        carePlans = (try? await store.fetchCarePlans(query: query)) ?? []
    }

    func createCarePlan(title: String) async {
        guard let store = AppDelegateKey.defaultValue?.store else {
            error = AppError.couldntBeUnwrapped
            return
        }
        let patientUUID = (try? await store
            .fetchPatients(query: OCKPatientQuery(for: Date())))?.first?.uuid
        let plan = OCKCarePlan(
            id: UUID().uuidString,
            title: title,
            patientUUID: patientUUID
        )
        do {
            _ = try await store.addCarePlans([plan])
            Logger.careKitTask.info("Created care plan: \(plan.title, privacy: .private)")
            await fetchCarePlans()
        } catch {
            self.error = AppError.errorString("Could not create care plan: \(error.localizedDescription)")
        }
    }
}
