//
//  OCKHealthKitPassthroughStore.swift
//  OCKSample
//
//  Created by Corey Baker on 1/5/22.
//  Copyright © 2022 Network Reconnaissance Lab. All rights reserved.
//

import Foundation
import CareKitEssentials
import CareKitStore
import HealthKit
import os.log

extension OCKHealthKitPassthroughStore {

    /*
     TODOxOK: You need to tie an OCKPatient and CarePlan to these tasks,
     */

    func populateDefaultHealthKitTasks(
        _ patientUUID: UUID? = nil,
        startDate: Date = Date()
	) async throws {

        let countUnit = HKUnit.count()
        let carePlanUUIDs = try await OCKStore.getCarePlanUUIDs()

        let stepTargetValue = OCKOutcomeValue(2000.0, units: countUnit.unitString)
        let stepSchedule = OCKSchedule.dailyAtTime(
            hour: 8, minutes: 0, start: startDate, end: nil,
            text: nil, duration: .allDay, targetValues: [stepTargetValue]
        )
        var steps = OCKHealthKitTask(
            id: TaskID.steps,
            title: String(localized: "STEPS"),
            carePlanUUID: carePlanUUIDs[.health],
            schedule: stepSchedule,
            healthKitLinkage: OCKHealthKitLinkage(
                quantityIdentifier: .stepCount,
                quantityType: .cumulative,
                unit: countUnit
            )
        )
        steps.asset = "figure.walk"
        steps.card = .numericProgress
        steps.priority = 31
        steps.instructions = String(localized: "STEPS_INSTRUCTIONS")
        steps.carePlanUUID = carePlanUUIDs[.health]
        steps.impactsAdherence = true

        // Primary: HRV (higher = less stress, target >= 40ms)
        // Supporting: restingHeartRate, heartRate (tracked via observer in AppDelegate)
        let hrvUnit = HKUnit.secondUnit(with: .milli)
        let hrvTarget = OCKOutcomeValue(40.0, units: hrvUnit.unitString) // 40ms HRV = healthy baseline
        let hrvSchedule = OCKSchedule.dailyAtTime(
            hour: 8, minutes: 0, start: startDate, end: nil,
            text: nil, duration: .allDay, targetValues: [hrvTarget]
        )
        var stressTask = OCKHealthKitTask(
            id: TaskID.stress,
            title: String(localized: "STRESS_EMOTIONAL_STATE"),
            carePlanUUID: carePlanUUIDs[.behavioralTracking],
            schedule: hrvSchedule,
            healthKitLinkage: OCKHealthKitLinkage(
                quantityIdentifier: .heartRateVariabilitySDNN,
                quantityType: .discrete,
                unit: hrvUnit
            )
        )
        stressTask.asset = "waveform.path.ecg"
        stressTask.card = .labeledValue
        stressTask.priority = 32
        stressTask.instructions = String(localized: "STRESS_INSTRUCTIONS")
        stressTask.impactsAdherence = false
        stressTask.carePlanUUID = carePlanUUIDs[.behavioralTracking]

        // Primary: stepCount (cumulative activity = engagement proxy)
        // Supporting: appleStandTime (target: stand 12 hours/day = 720 min)
        let attentionStepTarget = OCKOutcomeValue(5000.0, units: countUnit.unitString)
        let attentionSchedule = OCKSchedule.dailyAtTime(
            hour: 8, minutes: 0, start: startDate, end: nil,
            text: nil, duration: .allDay, targetValues: [attentionStepTarget]
        )
        var attentionTask = OCKHealthKitTask(
            id: TaskID.attention,
            title: String(localized: "ATTENTION_ENGAGEMENT"),
            carePlanUUID: carePlanUUIDs[.wellness],
            schedule: attentionSchedule,
            healthKitLinkage: OCKHealthKitLinkage(
                quantityIdentifier: .stepCount,
                quantityType: .cumulative,
                unit: countUnit
            )
        )
        attentionTask.asset = "figure.stand"
        attentionTask.card = .numericProgress
        attentionTask.priority = 33
        attentionTask.instructions = String(localized: "ATTENTION_INSTRUCTIONS")
        attentionTask.impactsAdherence = true
        attentionTask.carePlanUUID = carePlanUUIDs[.wellness]

        // Primary: appleExerciseTime (target: 30 min/day)
        // Supporting: timeInDaylight (target: 30 min/day)
        let minuteUnit = HKUnit.minute()
        let exerciseTarget = OCKOutcomeValue(30.0, units: minuteUnit.unitString)
        let routineSchedule = OCKSchedule.dailyAtTime(
            hour: 8, minutes: 0, start: startDate, end: nil,
            text: nil, duration: .allDay, targetValues: [exerciseTarget]
        )
        var routineTask = OCKHealthKitTask(
            id: TaskID.routine,
            title: String(localized: "ROUTINE_REGULATION"),
            carePlanUUID: carePlanUUIDs[.wellness],
            schedule: routineSchedule,
            healthKitLinkage: OCKHealthKitLinkage(
                quantityIdentifier: .appleExerciseTime,
                quantityType: .cumulative,
                unit: minuteUnit
            )
        )
        routineTask.asset = "sun.and.horizon.fill"
        routineTask.card = .numericProgress
        routineTask.priority = 34
        routineTask.instructions = String(localized: "ROUTINE_INSTRUCTIONS")
        routineTask.impactsAdherence = true
        routineTask.carePlanUUID = carePlanUUIDs[.wellness]

        let tasks = [steps, stressTask, attentionTask, routineTask]
        _ = try await addTasksIfNotPresent(tasks)
    }
}
