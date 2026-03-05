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
                TextField("Title",
                          text: $title)
                TextField("Instructions",
                          text: $instructions)
                DatePicker("Scheduled",
                           selection: $selectedTime,
                           displayedComponents: [.date, .hourAndMinute])
                Picker("Card View", selection: $selectedCard) {
                    ForEach(CareKitCard.allCases) { item in
                        Text(item.rawValue)
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
                Section("Task") {
                    Button("Add") {
                        addTask {
                            await viewModel.addTask(
                                title,
                                instructions: instructions,
                                scheduleTime: selectedTime,
                                cardType: selectedCard,
                                asset: selectedAsset.rawValue
                            )
                        }
                    }.alert(
                        "Task has been added",
                        isPresented: $isShowingAlert
                    ) {
                        Button("OK") {
                            isShowingAlert = false
                        }
                    }.disabled(isAddingTask)
                }
                Section("HealthKitTask") {
                    Button("Add") {
                        addTask {
                            await viewModel.addHealthKitTask(
                                title,
                                instructions: instructions,
                                scheduleTime: selectedTime,
                                cardType: selectedCard,
                                asset: selectedAsset.rawValue
                            )
                        }
                    }.alert(
                        "HealthKitTask has been added",
                        isPresented: $isShowingAlert
                    ) {
                        Button("OK") {
                            isShowingAlert = false
                        }
                    }.disabled(isAddingTask)
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

#Preview {
    CareKitTaskView()
}
