//
//  CarePlanDetailView.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import SwiftUI

struct CarePlanDetailView: View {

    let carePlan: OCKCarePlan

    @State private var tasks: [OCKTask] = []
    @State private var showingAddTask = false

    var body: some View {
        List {
            if tasks.isEmpty {
                Text("No tasks yet — tap + to add one")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks, id: \.id) { task in
                    HStack(spacing: 12) {
                        Image(systemName: task.asset ?? "checkmark.circle")
                            .font(.title2)
                            .foregroundStyle(.accent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title ?? "Untitled")
                                .font(.headline)
                            if let instructions = task.instructions {
                                Text(instructions)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(carePlan.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddTask = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            CareKitTaskView(initialCarePlanUUID: carePlan.uuid)
                .onDisappear {
                    Task { await fetchTasks() }
                }
        }
        .task {
            await fetchTasks()
        }
    }

    @MainActor
    private func fetchTasks() async {
        guard let store = AppDelegateKey.defaultValue?.store else { return }
                let carePlanUUID = carePlan.uuid
        var query = OCKTaskQuery(for: Date())
        query.carePlanUUIDs = [carePlanUUID]
        tasks = (try? await store.fetchTasks(query: query)) ?? []
    }
}
