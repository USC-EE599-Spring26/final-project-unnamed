//
//  CarePlanManagementView.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import SwiftUI

struct CarePlanManagementView: View {

    @StateObject var viewModel = CarePlanManagementViewModel()
    @State private var showingCreate = false
    @State private var newTitle = ""

    var body: some View {
        NavigationView {
            List {
                if viewModel.carePlans.isEmpty {
                    Text("No care plans yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.carePlans, id: \.id) { plan in
                        NavigationLink {
                            CarePlanDetailView(carePlan: plan)
                        } label: {
                            Label(plan.title, systemImage: "list.clipboard")
                        }
                    }
                }
            }
            .navigationTitle("Care Plans")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateCarePlanSheet(viewModel: viewModel, isPresented: $showingCreate)
            }
            .task {
                await viewModel.fetchCarePlans()
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.error = nil }
            } message: {
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Create Sheet

struct CreateCarePlanSheet: View {

    @ObservedObject var viewModel: CarePlanManagementViewModel
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var isCreating = false

    var body: some View {
        NavigationView {
            Form {
                Section("Care Plan Details") {
                    TextField("Title", text: $title)
                }
            }
            .navigationTitle("New Care Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        isCreating = true
                        Task {
                            await viewModel.createCarePlan(title: title)
                            isCreating = false
                            isPresented = false
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
        }
    }
}
