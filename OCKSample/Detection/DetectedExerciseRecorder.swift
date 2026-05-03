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
/// Design note: `detectedExercise` is an all-day daily task. CareKit allocates
/// one outcome slot per scheduled event (per day). Multiple detected sessions
/// on the same day can't each be a separate OCKOutcome — they'd collide on
/// (taskUUID, occurrenceIndex). Instead, each session is one `OCKOutcomeValue`
/// appended to that day's single outcome. Per-session metadata
/// (start/end/unconfirmed) is JSON-encoded into the value's `kind`.
///
/// IMPORTANT: `taskOccurrenceIndex` is the position of the event in the
/// ENTIRE schedule (counting from `schedule.start`), NOT a per-day index. For
/// a schedule started on day 1, today on day N has occurrence N-1. Hardcoding
/// 0 means "the schedule's first day" — every write would collide there.
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

    /// Compute the occurrence index for today's event on this task's schedule.
    /// For a daily allDay task with schedule starting at day D, today (day D+N)
    /// has occurrence N. This is NOT always 0.
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
