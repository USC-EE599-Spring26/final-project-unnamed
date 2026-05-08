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
import CareKitUI

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

        let endDate: Date? = repeatPeriod == .never
            ? calendar.date(byAdding: .day, value: 1, to: startDate)
            : repeatEnd

        if repeatPeriod == .never || repeatPeriod == .daily {
            return .dailyAtTime(
                hour: hour,
                minutes: minute,
                start: startDate,
                end: endDate,
                text: nil
            )
        }

        var interval = DateComponents()
        interval.hour = hour
        interval.minute = minute

        switch repeatPeriod {
        case .weekly:   interval.weekOfYear = 1
        case .monthly:  interval.month = 1
        case .yearly:   interval.year = 1
        default:        break
        }

        let element = OCKScheduleElement(start: startDate, end: endDate, interval: interval)
        return OCKSchedule(composing: [element])
    }

    // MARK: Intents
    func addTask(
        _ title: String,
        instructions: String,
        scheduleTime: Date,
        cardType: CareKitCard,
        asset: String? = nil,
        repeatPeriod: RepeatPeriod = .never,
        repeatEnd: Date? = nil,
        carePlanUUID: UUID? = nil,
        linkTitle: String? = nil,
        linkURL: String? = nil,
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
            carePlanUUID: carePlanUUID,
            schedule: schedule
        )
        task.instructions = instructions
        task.card = cardType
        task.asset = asset
        task.priority = 0

        switch cardType {
        case .survey, .uiKitSurvey, .link, .button:
            task.impactsAdherence = false
        default:
            task.impactsAdherence = true
        }

        if cardType == .link,
           let linkTitle = linkTitle,
           let linkURL = linkURL {
                task.userInfo = [
                    "linkTitle": linkTitle,
                    "linkURL": linkURL
                ]
        }

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
        repeatEnd: Date? = nil,
        carePlanUUID: UUID? = nil,
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
            carePlanUUID: carePlanUUID,
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
        healthKitTask.priority = 0
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
