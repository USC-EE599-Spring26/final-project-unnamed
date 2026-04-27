//
//  PatientDetailView.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import SwiftUI

struct PatientDetailView: View {

    let patient: PatientManagementViewModel.PatientRow

    @StateObject private var viewModel: PatientDetailViewModel

    init(patient: PatientManagementViewModel.PatientRow) {
        self.patient = patient
        _viewModel = StateObject(
            wrappedValue: PatientDetailViewModel(patient: patient)
        )
    }

    var body: some View {
        List {
            // ── Patient info ────────────────────────────────────────────
            Section("Patient Info") {
                LabeledContent("Username", value: patient.username)
                if let email = patient.email {
                    LabeledContent("Email", value: email)
                }
                if let phone = patient.phoneNumber {
                    LabeledContent("Phone", value: phone)
                }
            }

            // ── Care plan assignment ────────────────────────────────────
            Section {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.carePlans.isEmpty {
                    Text("No care plans yet — create one in the Care Plans tab.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.carePlans) { item in
                        Button {
                            Task { await viewModel.toggleAssignment(for: item) }
                        } label: {
                            HStack {
                                Label(item.title, systemImage: "list.clipboard")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.isProcessing {
                                    ProgressView()
                                        .frame(width: 22, height: 22)
                                } else {
                                    assignmentIcon(for: item.assignmentStatus)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isProcessing)
                    }
                }
            } header: {
                Text("Care Plans")
            } footer: {
                Text(
                    "Tap to assign or revoke. Patient must accept before the plan is active."
                )
            }
        }
        .navigationTitle(patient.displayName)
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.fetchCarePlans() }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func assignmentIcon(for status: String?) -> some View {
        switch status {
        case CarePlanAssignment.statusAccepted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case CarePlanAssignment.statusPending:
            Image(systemName: "clock.badge")
                .foregroundStyle(.orange)
                .font(.title3)
        case CarePlanAssignment.statusRejected:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.red)
                .font(.title3)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }
}
