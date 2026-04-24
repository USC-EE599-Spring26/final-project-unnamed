//
//  DetectedExerciseRecorder.swift
//  OCKSample
//
//  Created by Student on 4/23/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import Foundation
import os.log

/// Writes auto-detected exercise sessions into OCKStore as outcomes on the
/// `TaskID.detectedExercise` task.
///
/// This is the only component that knows the on-disk shape of a detected
/// session. Detector and notification layers call into this type; if we later
/// change the schema (e.g. sync to Parse, add HR data), it stays local here.
@MainActor
struct DetectedExerciseRecorder {

    // Keys inside OCKOutcome.userInfo.
    enum UserInfoKey {
        static let startDate = "detected.startDate"
        static let endDate = "detected.endDate"
        static let isUnconfirmed = "detected.isUnconfirmed"
        static let source = "detected.source"
    }

    enum Source: String {
        /// User tapped "Log" on the notification.
        case userConfirmed = "user_confirmed"
        /// Notification was ignored; we still persist what we observed.
        case autoRecorded = "auto_recorded"
    }

    let store: OCKStore

    /// Persist a detected exercise session.
    ///
    /// - parameter start: when step activity actually began rising
    /// - parameter end: when step rate dropped back to baseline
    /// - parameter isUnconfirmed: true if the user never responded to the prompt
    func record(
        start: Date,
        end: Date,
        isUnconfirmed: Bool
    ) async throws {
        let task = try await fetchTask()

        let duration = end.timeIntervalSince(start)
        var value = OCKOutcomeValue(duration, units: "seconds")
        value.createdDate = end

        // taskOccurrenceIndex: which scheduled event this outcome attaches to.
        // detectedExercise is all-day daily, so occurrence 0 = today's event.
        // We compute the offset from the task's schedule start to `start`.
        let occurrence = task.schedule.events(
            from: task.schedule.startDate(),
            to: start
        ).count

        var outcome = OCKOutcome(
            taskUUID: task.uuid,
            taskOccurrenceIndex: max(0, occurrence - 1),
            values: [value]
        )
        outcome.effectiveDate = end
        outcome.userInfo = [
            UserInfoKey.startDate: ISO8601DateFormatter().string(from: start),
            UserInfoKey.endDate: ISO8601DateFormatter().string(from: end),
            UserInfoKey.isUnconfirmed: String(isUnconfirmed),
            UserInfoKey.source: (isUnconfirmed ? Source.autoRecorded : Source.userConfirmed).rawValue
        ]

        _ = try await store.addOutcome(outcome)
        Logger.detection.info(
            "Recorded detected exercise: \(start) → \(end), unconfirmed=\(isUnconfirmed)"
        )
    }

    private func fetchTask() async throws -> OCKTask {
        var query = OCKTaskQuery(for: Date())
        query.ids = [TaskID.detectedExercise]
        let tasks = try await store.fetchTasks(query: query)
        guard let task = tasks.first else {
            throw AppError.errorString("detectedExercise task not found in store")
        }
        return task
    }
}
