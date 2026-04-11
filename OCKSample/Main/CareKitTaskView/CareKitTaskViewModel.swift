//
//  CareKitTaskViewModel.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/2/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import Foundation
import CareKitStore
import os.log

@MainActor
class CareKitTaskViewModel: ObservableObject {

    @Published var error: AppError?

    private func makeSchedule(
        scheduleTime: Date,
        repeatPeriod: RepeatPeriod,
        repeatEnd: Date?
    ) -> OCKSchedule {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: scheduleTime)
        let hour = calendar.component(.hour, from: scheduleTime)
        let minute = calendar.component(.minute, from: scheduleTime)

        // End date: nil means the task repeats indefinitely
        let endDate: Date? = repeatPeriod == .never
            ? calendar.date(byAdding: .day, value: 1, to: startDate)
            : repeatEnd

        switch repeatPeriod {
        case .never, .daily:
            return .dailyAtTime(
                hour: hour,
                minutes: minute,
                start: startDate,
                end: endDate,
                text: nil
            )

        case .weekly:
            var interval = DateComponents()
            interval.weekOfYear = 1
            interval.hour = hour
            interval.minute = minute
            let element = OCKScheduleElement(
                start: startDate,
                end: endDate,
                interval: interval
            )
            return OCKSchedule(composing: [element])

        case .monthly:
            var interval = DateComponents()
            interval.month = 1
            interval.hour = hour
            interval.minute = minute
            let element = OCKScheduleElement(
                start: startDate,
                end: endDate,
                interval: interval
            )
            return OCKSchedule(composing: [element])

        case .yearly:
            var interval = DateComponents()
            interval.year = 1
            interval.hour = hour
            interval.minute = minute
            let element = OCKScheduleElement(
                start: startDate,
                end: endDate,
                interval: interval
            )
            return OCKSchedule(composing: [element])
        }
    }

    // MARK: Intents
    func addTask(
        _ title: String,
        instructions: String,
        scheduleTime: Date,
        cardType: CareKitCard,
        asset: String? = nil,
        repeatPeriod: RepeatPeriod = .never,
        repeatEnd: Date? = nil
    ) async {
        guard let appDelegate = AppDelegateKey.defaultValue else {
            error = AppError.couldntBeUnwrapped
            return
        }
        let uniqueId = UUID().uuidString
        let schedule = makeSchedule(
            scheduleTime: scheduleTime,
            repeatPeriod: repeatPeriod,
            repeatEnd: repeatEnd
        )
        var task = OCKTask(
            id: uniqueId,
            title: title,
            carePlanUUID: nil,
            schedule: schedule
        )
        task.instructions = instructions
        task.card = cardType
        task.asset = asset
        do {
            _ = try await appDelegate.store.addTasksIfNotPresent([task])
            Logger.careKitTask.info("Saved task: \(task.id, privacy: .private)")
            NotificationCenter.default.post(.init(name: Notification.Name(rawValue: Constants.shouldRefreshView)))
        } catch {
            self.error = AppError.errorString("Could not add task: \(error.localizedDescription)")
        }
    }

    func addHealthKitTask(
        _ title: String,
        instructions: String,
        scheduleTime: Date,
        cardType: CareKitCard,
        asset: String? = nil,
        repeatPeriod: RepeatPeriod = .never,
        repeatEnd: Date? = nil
    ) async {
        guard let appDelegate = AppDelegateKey.defaultValue else {
            error = AppError.couldntBeUnwrapped
            return
        }
        let uniqueId = UUID().uuidString
        let schedule = makeSchedule(
            scheduleTime: scheduleTime,
            repeatPeriod: repeatPeriod,
            repeatEnd: repeatEnd
        )
        var healthKitTask = OCKHealthKitTask(
            id: uniqueId,
            title: title,
            carePlanUUID: nil,
            schedule: schedule,
            healthKitLinkage: .init(
                quantityIdentifier: .electrodermalActivity,
                quantityType: .discrete,
                unit: .count()
            )
        )
        healthKitTask.instructions = instructions
        healthKitTask.card = cardType
        healthKitTask.asset = asset
        do {
            _ = try await appDelegate.healthKitStore.addTasksIfNotPresent([healthKitTask])
            Logger.careKitTask.info("Saved HealthKitTask: \(healthKitTask.id, privacy: .private)")
            NotificationCenter.default.post(.init(name: Notification.Name(rawValue: Constants.shouldRefreshView)))
            Utility.requestHealthKitPermissions()
        } catch {
            self.error = AppError.errorString("Could not add healthKitTask: \(error.localizedDescription)")
        }
    }
}
