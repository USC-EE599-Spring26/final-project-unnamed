//
//  DetectedMoodRecorder.swift
//  OCKSample
//
//  Created by Student on 4/27/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import Foundation
import os.log

/// Writes auto-detected mood-spike events into OCKStore. Mirrors
/// `DetectedExerciseRecorder`: one all-day daily task, multiple events per day
/// stored as appended `OCKOutcomeValue`s with metadata JSON-encoded into `kind`.
@MainActor
struct DetectedMoodRecorder {

    struct SpikeMetadata: Codable {
        let detectedAt: Date
        let hrAvg: Double
        let hrBaseline: Double
        let stepsInWindow: Double
        let isUnconfirmed: Bool
        let source: String
    }

    let store: OCKStore

    func record(
        detectedAt: Date,
        hrAvg: Double,
        hrBaseline: Double,
        stepsInWindow: Double,
        isUnconfirmed: Bool
    ) async throws {
        let task = try await fetchTask()

        let metadata = SpikeMetadata(
            detectedAt: detectedAt,
            hrAvg: hrAvg,
            hrBaseline: hrBaseline,
            stepsInWindow: stepsInWindow,
            isUnconfirmed: isUnconfirmed,
            source: isUnconfirmed ? "auto_recorded" : "user_confirmed"
        )
        let kindJSON = try encode(metadata)

        var value = OCKOutcomeValue(hrAvg, units: "bpm")
        value.createdDate = detectedAt
        value.kind = kindJSON

        let occurrence = try todaysOccurrence(for: task)

        if let existing = try await fetchTodaysOutcome(occurrence: occurrence) {
            var updated = existing
            updated.values.append(value)
            updated.effectiveDate = detectedAt
            _ = try await store.updateOutcome(updated)
            Logger.detection.info(
                "Appended mood spike to existing outcome at \(detectedAt), hr=\(hrAvg) baseline=\(hrBaseline)"
            )
        } else {
            var outcome = OCKOutcome(
                taskUUID: task.uuid,
                taskOccurrenceIndex: occurrence,
                values: [value]
            )
            outcome.effectiveDate = detectedAt
            _ = try await store.addOutcome(outcome)
            Logger.detection.info(
                "Created mood spike outcome at \(detectedAt), hr=\(hrAvg) baseline=\(hrBaseline)"
            )
        }
    }

    /// Compute today's occurrence index from the task's schedule. CareKit's
    /// `taskOccurrenceIndex` counts from schedule start, not per-day, so this
    /// is non-zero on any day after the schedule's first.
    private func todaysOccurrence(for task: OCKTask) throws -> Int {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let todaysEvents = task.schedule.events(from: dayStart, to: dayEnd)
        guard let occurrence = todaysEvents.first?.occurrence else {
            throw AppError.errorString("No schedule event for today on detectedMoodSpike")
        }
        return occurrence
    }

    private func fetchTask() async throws -> OCKTask {
        var query = OCKTaskQuery(for: Date())
        query.ids = [TaskID.detectedMoodSpike]
        let tasks = try await store.fetchTasks(query: query)
        guard let task = tasks.first else {
            throw AppError.errorString("detectedMoodSpike task not found in store")
        }
        return task
    }

    /// Look up today's outcome by task ID (not version UUID) so we find rows
    /// even when CareKit has re-versioned the task — e.g. after a Parse sync
    /// pulls a different cloud-side version. Querying by UUID would miss the
    /// historical outcome and we'd fall through to addOutcome → CareKit
    /// rejects with "A duplicate outcome exists" since uniqueness is checked
    /// on (taskID, occurrenceIndex) across versions.
    private func fetchTodaysOutcome(occurrence: Int) async throws -> OCKOutcome? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var query = OCKOutcomeQuery(dateInterval: DateInterval(start: dayStart, end: dayEnd))
        query.taskIDs = [TaskID.detectedMoodSpike]
        let outcomes = try await store.fetchOutcomes(query: query)
        return outcomes.first { $0.taskOccurrenceIndex == occurrence }
    }

    private func encode(_ metadata: SpikeMetadata) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
