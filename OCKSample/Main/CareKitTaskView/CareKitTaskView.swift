//
//  CareKitTaskView.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/2/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import SwiftUI

struct CareKitTaskView: View {

    // MARK: Navigation
    @State var isShowingAlert = false
    @State var isAddingTask = false
    @State var alertMessage = ""

    // MARK: View
    @StateObject var viewModel = CareKitTaskViewModel()
    @State var title = ""
    @State var instructions = ""
    @State var selectedTime = Date()
    @State var selectedCard: CareKitCard = .button
    @State var selectedAsset: CareKitAsset = .walk

    var body: some View {
        NavigationView {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $title)
                    TextField("Instructions", text: $instructions)
                    DatePicker("Scheduled", selection: $selectedTime, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Style & Icon") {
                    Picker("Card View", selection: $selectedCard) {
                        ForEach(CareKitCard.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Asset", selection: $selectedAsset) {
                        ForEach(CareKitAsset.allCases) { asset in
                            Label {
                                Text(asset.displayName)
                            } icon: {
                                Image(systemName: asset.rawValue)
                            }
                            .tag(asset)
                        }
                    }
                }

                Section("Add Task") {
                    Button("Add Regular Task") {
                        alertMessage = "Task has been added"
                        addTask {
                            await viewModel.addTask(
                                title,
                                instructions: instructions,
                                scheduleTime: selectedTime,
                                cardType: selectedCard,
                                asset: selectedAsset.rawValue
                            )
                            title = ""
                        }
                    }

                    Button("Add HealthKit Task") {
                        alertMessage = "HealthKitTask has been added"
                        addTask {
                            await viewModel.addHealthKitTask(
                                title,
                                instructions: instructions,
                                scheduleTime: selectedTime,
                                cardType: selectedCard,
                                asset: selectedAsset.rawValue
                            )
                            title = ""
                        }
                    }
                }
                .disabled(isAddingTask || title.isEmpty)
            }
            .navigationTitle("New Task")
            .alert(alertMessage, isPresented: $isShowingAlert) {
                Button("OK") {
                    isShowingAlert = false
                }
            }
        }
    }

    // MARK: Helpers
    func addTask(_ task: @escaping (() async -> Void)) {
        isAddingTask = true
        Task {
            await task()
            isAddingTask = false
            isShowingAlert = true
        }
    }
}
