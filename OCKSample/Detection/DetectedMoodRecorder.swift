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

        let occurrence = 0

        if let existing = try await fetchTodaysOutcome(taskUUID: task.uuid, occurrence: occurrence) {
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

    private func fetchTask() async throws -> OCKTask {
        var query = OCKTaskQuery(for: Date())
        query.ids = [TaskID.detectedMoodSpike]
        let tasks = try await store.fetchTasks(query: query)
        guard let task = tasks.first else {
            throw AppError.errorString("detectedMoodSpike task not found in store")
        }
        return task
    }

    private func fetchTodaysOutcome(
        taskUUID: UUID,
        occurrence: Int
    ) async throws -> OCKOutcome? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var query = OCKOutcomeQuery(dateInterval: DateInterval(start: dayStart, end: dayEnd))
        query.taskUUIDs = [taskUUID]
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
