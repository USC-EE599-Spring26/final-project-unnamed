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

/// Writes auto-detected exercise sessions into OCKStore.
///
/// `detectedExercise` is an all-day daily task — CareKit gives it one outcome
/// per day. Multiple sessions can't each be a separate OCKOutcome (they'd
/// collide on taskUUID + occurrenceIndex), so each session is an OCKOutcomeValue
/// appended to that day's single outcome, with metadata JSON-encoded into `kind`.
///
/// NOTE: `taskOccurrenceIndex` counts from schedule start across all days —
/// hardcoding 0 always means "day 1" and causes collisions.
@MainActor
struct DetectedExerciseRecorder {

    struct SessionMetadata: Codable {
        let start: Date
        let end: Date
        let isUnconfirmed: Bool
        let source: String  // "user_confirmed" | "auto_recorded"
    }

    let store: OCKStore

    func record(
        start: Date,
        end: Date,
        isUnconfirmed: Bool
    ) async throws {
        let task = try await fetchTask()

        let metadata = SessionMetadata(
            start: start,
            end: end,
            isUnconfirmed: isUnconfirmed,
            source: isUnconfirmed ? "auto_recorded" : "user_confirmed"
        )
        let kindJSON = try encode(metadata)

        let duration = end.timeIntervalSince(start)
        var value = OCKOutcomeValue(duration, units: "seconds")
        value.createdDate = end
        value.kind = kindJSON

        let occurrence = try todaysOccurrence(for: task)

        if let existing = try await fetchTodaysOutcome(occurrence: occurrence) {
            var updated = existing
            updated.values.append(value)
            updated.effectiveDate = end
            _ = try await store.updateOutcome(updated)
            Logger.detection.info(
                "Appended session to existing outcome: \(start) → \(end), unconfirmed=\(isUnconfirmed)"
            )
        } else {
            var outcome = OCKOutcome(
                taskUUID: task.uuid,
                taskOccurrenceIndex: occurrence,
                values: [value]
            )
            outcome.effectiveDate = end
            _ = try await store.addOutcome(outcome)
            Logger.detection.info(
                "Created outcome for detected exercise: \(start) → \(end), unconfirmed=\(isUnconfirmed)"
            )
        }
    }

    /// Occurrence index for today's event — NOT always 0 for a daily task.
    private func todaysOccurrence(for task: OCKTask) throws -> Int {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let todaysEvents = task.schedule.events(from: dayStart, to: dayEnd)
        guard let occurrence = todaysEvents.first?.occurrence else {
            throw AppError.errorString("No schedule event for today on detectedExercise")
        }
        return occurrence
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

    /// Query by task ID (not UUID) so we find the outcome even if CareKit
    /// re-versioned the task after a Parse sync — querying by UUID would miss it
    /// and addOutcome would fail with "duplicate outcome exists".
    private func fetchTodaysOutcome(occurrence: Int) async throws -> OCKOutcome? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var query = OCKOutcomeQuery(dateInterval: DateInterval(start: dayStart, end: dayEnd))
        query.taskIDs = [TaskID.detectedExercise]
        let outcomes = try await store.fetchOutcomes(query: query)
        return outcomes.first { $0.taskOccurrenceIndex == occurrence }
    }

    private func encode(_ metadata: SessionMetadata) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
