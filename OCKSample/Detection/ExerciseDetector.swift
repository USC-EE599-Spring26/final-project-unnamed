//
//  ExerciseDetector.swift
//  OCKSample
//
//  Created by Student on 4/23/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import Foundation
import HealthKit
import os.log
// swiftlint:disable identifier_name

/// Watches step data in the background and prompts the user to log exercise
/// when it looks like they're being active without having started a task.
///
/// Lifecycle:
///   1. `start()` registers an HKObserverQuery with background delivery.
///      iOS wakes the app whenever new step samples arrive (~few min cadence).
///   2. Each wake-up runs `evaluate()` which looks at the past 5 min of steps.
///   3. A tiny state machine decides whether to prompt, wait for end, or idle.
/// Unsafe escape hatch for closures that Apple frameworks hand us without
/// `@Sendable`, but which are documented safe to call across threads.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

@MainActor
final class ExerciseDetector {

    // MARK: Tuning constants (v1 fixed thresholds)

    /// Steps in the detection window required to trigger a prompt.
    private static let stepTriggerThreshold: Double = 300
    /// Window used for the trigger check.
    private static let detectionWindow: TimeInterval = 5 * 60
    /// Steps-per-check below which we consider movement to have ended.
    private static let stepEndedThreshold: Double = 30
    /// Window used for the end check.
    private static let endWindow: TimeInterval = 3 * 60
    /// After a dismissed prompt, suppress re-prompts for this long.
    private static let dismissDebounce: TimeInterval = 30 * 60
    /// If the user never responds and movement has ended, still write an
    /// unconfirmed record once the prompt has been outstanding this long.
    private static let unconfirmedTimeout: TimeInterval = 20 * 60
    /// Suppress triggering if any exercise-related task has an outcome within
    /// this window (user is already logging manually).
    private static let activeTaskSuppressionWindow: TimeInterval = 30 * 60

    // MARK: State machine

    private enum Phase: String, Codable {
        case idle
        case pendingConfirmation  // notification posted, waiting on user
        case monitoringEnd        // user confirmed, waiting for movement to stop
    }

    private struct PersistedState: Codable {
        var phase: Phase = .idle
        var sessionStart: Date?
        var notificationPostedAt: Date?
        var lastDismissAt: Date?
    }

    // MARK: Dependencies

    private let healthStore = HKHealthStore()
    private let ockStore: OCKStore
    private let recorder: DetectedExerciseRecorder
    private let notifications: DetectionNotificationManager

    private var observerQuery: HKObserverQuery?
    private var state: PersistedState {
        didSet { Self.persist(state) }
    }

    init(
        ockStore: OCKStore,
        notifications: DetectionNotificationManager
    ) {
        self.ockStore = ockStore
        self.notifications = notifications
        self.recorder = DetectedExerciseRecorder(store: ockStore)
        self.state = Self.loadPersisted() ?? PersistedState()
    }

    // MARK: Public lifecycle

    func start() async {
        Logger.detection.info("ExerciseDetector.start() called")
        notifications.handler = self

        guard HKHealthStore.isHealthDataAvailable() else {
            Logger.detection.warning("HealthKit unavailable on this device")
            return
        }

        let stepType = HKQuantityType(.stepCount)
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [stepType])
            Logger.detection.info("HealthKit step read auth requested")
        } catch {
            Logger.detection.error("HealthKit auth failed: \(error)")
            return
        }

        // Background delivery → iOS wakes us when new samples arrive.
        do {
            try await healthStore.enableBackgroundDelivery(for: stepType, frequency: .immediate)
        } catch {
            Logger.detection.error("enableBackgroundDelivery failed: \(error)")
        }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completion, error in
            // HealthKit's completion handler type isn't Sendable, but Apple
            // documents it as safe to call from any thread. Wrap it so we can
            // invoke it after awaiting on MainActor.
            let safeCompletion = UncheckedSendableBox(completion)
            if let error {
                Logger.detection.error("Observer query error: \(error)")
                safeCompletion.value()
                return
            }
            Task { @MainActor [weak self] in
                await self?.evaluate()
                safeCompletion.value()
            }
        }
        healthStore.execute(query)
        self.observerQuery = query

        // Also run once on start so we don't wait for the first HK update.
        await evaluate()
    }

    // MARK: Core evaluation (runs on every wake-up)

    private func evaluate() async {
        let now = Date()
        switch state.phase {
        case .idle:
            await evaluateIdle(now: now)
        case .pendingConfirmation:
            await evaluatePending(now: now)
        case .monitoringEnd:
            await evaluateMonitoring(now: now)
        }
    }

    private func evaluateIdle(now: Date) async {
        // Debounce after a recent dismiss.
        if let last = state.lastDismissAt, now.timeIntervalSince(last) < Self.dismissDebounce {
            Logger.detection.info("Idle: debounced (last dismiss \(last))")
            return
        }

        let recentSteps = await sumSteps(from: now.addingTimeInterval(-Self.detectionWindow), to: now)
        Logger.detection.info("Idle: steps in last \(Int(Self.detectionWindow/60))min = \(recentSteps)")
        guard recentSteps >= Self.stepTriggerThreshold else { return }

        // User may already be logging this session manually.
        if await userIsAlreadyLoggingExercise(now: now) {
            Logger.detection.info("Suppressing prompt — exercise-related task active")
            return
        }

        let start = await estimatedMovementStart(endingAt: now) ?? now.addingTimeInterval(-Self.detectionWindow)
        state.sessionStart = start
        state.notificationPostedAt = now
        state.phase = .pendingConfirmation
        await notifications.postExerciseDetectedNotification()
        Logger.detection.info("Posted detection prompt; session start \(start)")
    }

    private func evaluatePending(now: Date) async {
        // If user ignored the prompt and movement has already ended for a
        // while, write an unconfirmed record so the data isn't lost.
        guard let postedAt = state.notificationPostedAt else {
            resetToIdle()
            return
        }
        guard now.timeIntervalSince(postedAt) >= Self.unconfirmedTimeout else { return }

        let recent = await sumSteps(from: now.addingTimeInterval(-Self.endWindow), to: now)
        guard recent < Self.stepEndedThreshold else { return }

        await writeRecord(end: now, isUnconfirmed: true)
        notifications.cancelExerciseDetectedNotification()
        resetToIdle()
    }

    private func evaluateMonitoring(now: Date) async {
        let recent = await sumSteps(from: now.addingTimeInterval(-Self.endWindow), to: now)
        guard recent < Self.stepEndedThreshold else { return }

        await writeRecord(end: now, isUnconfirmed: false)
        resetToIdle()
    }

    // MARK: DetectionNotificationHandler callbacks

    private func writeRecord(end: Date, isUnconfirmed: Bool) async {
        guard let start = state.sessionStart else { return }
        do {
            try await recorder.record(start: start, end: end, isUnconfirmed: isUnconfirmed)
        } catch {
            Logger.detection.error("Record write failed: \(error)")
        }
    }

    private func resetToIdle() {
        state.phase = .idle
        state.sessionStart = nil
        state.notificationPostedAt = nil
    }

    // MARK: Queries

    private func sumSteps(from: Date, to: Date) async -> Double {
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                let count = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: count)
            }
            healthStore.execute(query)
        }
    }

    /// Walks backward from `endingAt` in 1-minute buckets and returns the
    /// timestamp of the first bucket where steps first became non-trivial.
    /// Capped at 30 minutes of lookback.
    private func estimatedMovementStart(endingAt: Date) async -> Date? {
        let maxLookback: TimeInterval = 30 * 60
        let windowStart = endingAt.addingTimeInterval(-maxLookback)
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: endingAt, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            var interval = DateComponents()
            interval.minute = 1
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: windowStart,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                guard let results else {
                    continuation.resume(returning: nil)
                    return
                }
                var firstActive: Date?
                results.enumerateStatistics(from: windowStart, to: endingAt) { stats, _ in
                    let steps = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    if steps >= 10, firstActive == nil {
                        firstActive = stats.startDate
                    }
                }
                continuation.resume(returning: firstActive)
            }
            healthStore.execute(query)
        }
    }

    private func userIsAlreadyLoggingExercise(now: Date) async -> Bool {
        let windowStart = now.addingTimeInterval(-Self.activeTaskSuppressionWindow)
        var query = OCKOutcomeQuery(
            dateInterval: DateInterval(start: windowStart, end: now)
        )
        query.taskIDs = TaskID.exerciseRelated.filter { $0 != TaskID.detectedExercise }
        do {
            let outcomes = try await ockStore.fetchOutcomes(query: query)
            if !outcomes.isEmpty {
                Logger.detection.info("Found \(outcomes.count) recent exercise-related outcome(s) — suppressing")
            }
            return !outcomes.isEmpty
        } catch {
            Logger.detection.error("Outcome fetch for suppression failed: \(error)")
            return false
        }
    }

    // MARK: Persistence

    private static let persistenceKey = "ExerciseDetector.state"

    private static func loadPersisted() -> PersistedState? {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private static func persist(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }
}

extension ExerciseDetector: DetectionNotificationHandler {

    func userConfirmedDetectedExercise() async {
        guard state.phase == .pendingConfirmation else { return }

        // Check whether movement already ended: if so, write immediately using
        // a best-effort end time (now). Otherwise enter monitoring.
        let now = Date()
        let recent = await sumSteps(from: now.addingTimeInterval(-Self.endWindow), to: now)
        if recent < Self.stepEndedThreshold {
            await writeRecord(end: now, isUnconfirmed: false)
            resetToIdle()
        } else {
            state.phase = .monitoringEnd
            state.notificationPostedAt = nil
        }
    }

    func userDismissedDetectedExercise() async {
        state.lastDismissAt = Date()
        resetToIdle()
    }
}
