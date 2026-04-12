//
//  CareKitTaskView.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/2/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import SwiftUI
import CareKitStore

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
    @State var selectedRepeat: RepeatPeriod = .never
    @State var repeatEndDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State var carePlans: [OCKCarePlan] = []
    @State var selectedCarePlan: OCKCarePlan?
    @State var linkTitle: String = ""
    @State var linkURL: String = ""

    // MARK: Environment
    @Environment(\.careStore) var careStore

    private var isHealthKitCard: Bool {
        selectedCard == .labeledValue || selectedCard == .numericProgress
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $title)
                    TextField("Instructions", text: $instructions)
                    DatePicker(
                        "Scheduled",
                        selection: $selectedTime,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Repeat") {
                    Picker("Repeat", selection: $selectedRepeat) {
                        ForEach(RepeatPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }

                    if selectedRepeat != .never {
                        DatePicker(
                            "End Repeat",
                            selection: $repeatEndDate,
                            in: selectedTime...,
                            displayedComponents: .date
                        )
                    }
                }

                Section("Style & Icon") {
                    Picker("Card View", selection: $selectedCard) {
                        ForEach(CareKitCard.allCases.filter { $0 != .uiKitSurvey && $0 != .featured }) { item in
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

                Section("Care Plan") {
                    if carePlans.isEmpty {
                        Text("No care plans available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Care Plan", selection: $selectedCarePlan) {
                            Text("None").tag(Optional<OCKCarePlan>.none)
                            ForEach(carePlans, id: \.id) { plan in
                                Text(plan.title).tag(Optional(plan))
                            }
                        }
                    }
                }

                if selectedCard == .link {
                    Section("Link") {
                        TextField("Link Title", text: $linkTitle)
                        TextField("URL (https://...)", text: $linkURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                    }
                }

                Button("Add Task") {
                    alertMessage = "Task has been added"
                    addTask {
                        if isHealthKitCard {
                            await viewModel.addHealthKitTask(
                                title,
                                instructions: instructions,
                                scheduleTime: selectedTime,
                                cardType: selectedCard,
                                asset: selectedAsset.rawValue,
                                repeatPeriod: selectedRepeat,
                                repeatEnd: selectedRepeat == .never ? nil : repeatEndDate,
                                carePlanUUID: selectedCarePlan?.uuid
                            )
                        } else {
                            await viewModel.addTask(
                                title,
                                instructions: instructions,
                                scheduleTime: selectedTime,
                                cardType: selectedCard,
                                asset: selectedAsset.rawValue,
                                repeatPeriod: selectedRepeat,
                                repeatEnd: selectedRepeat == .never ? nil : repeatEndDate,
                                carePlanUUID: selectedCarePlan?.uuid,
                                linkTitle: selectedCard == .link ? linkTitle : nil,
                                linkURL: selectedCard == .link ? linkURL : nil
                            )
                        }
                        title = ""
                    }
                }
                .disabled(isAddingTask || title.isEmpty || instructions.isEmpty)
            }
            .navigationTitle("New Task")
            .alert(alertMessage, isPresented: $isShowingAlert) {
                Button("OK") { isShowingAlert = false }
            }
            .task {
                await fetchCarePlans()
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

    @MainActor
    func fetchCarePlans() async {
        guard let store = AppDelegateKey.defaultValue?.store else {
            return
        }
        let query = OCKCarePlanQuery(for: Date())
        carePlans = (try? await store.fetchCarePlans(query: query)) ?? []

        selectedCarePlan = carePlans.first(where: { $0.id == CarePlanID.custom.rawValue })
            ?? carePlans.first
    }
}
