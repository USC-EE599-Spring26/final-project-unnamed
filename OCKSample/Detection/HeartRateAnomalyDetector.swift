//
//  HeartRateAnomalyDetector.swift
//  OCKSample
//
//  Created by Student on 4/27/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import Foundation
import HealthKit
import os.log
// swiftlint:disable identifier_name

/// Watches HR in the background and prompts to log a mood event when HR spikes
/// above resting baseline without movement (ruling out exercise).
/// Single-stage — mood spikes are moments, not sessions, so no end-monitoring phase.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

@MainActor
final class HeartRateAnomalyDetector {

    // MARK: Tuning constants (v1 fixed thresholds)

    /// Bpm above resting-HR baseline required to call it a "spike".
    private static let hrSpikeDelta: Double = 25
    /// Used when restingHeartRate is unavailable (no Apple Watch / no samples).
    private static let hrFallbackBaseline: Double = 60
    /// Window over which we average HR samples to compare against threshold.
    private static let hrDetectionWindow: TimeInterval = 5 * 60
    /// Steps in the same HR window above which we suppress (treat as exercise).
    private static let stepSuppressionThreshold: Double = 50
    /// Cool-down after a spike is logged. Not applied on dismiss (false positive).
    private static let dismissDebounce: TimeInterval = 10 * 60
    /// Suppress if any exercise- or mood-related task has an outcome in this window.
    private static let activeTaskSuppressionWindow: TimeInterval = 10 * 60
    /// If the user never responds, write an unconfirmed record after this long.
    private static let unconfirmedTimeout: TimeInterval = 7 * 60

    // MARK: State machine

    fileprivate enum Phase: String, Codable {
        case idle
        case pendingConfirmation
    }

    fileprivate struct PersistedState: Codable {
        var phase: Phase = .idle
        var notificationPostedAt: Date?
        var lastDismissAt: Date?
        var lastDetectedHR: Double?
        var lastBaseline: Double?
        var lastStepsInWindow: Double?
        var lastDetectedAt: Date?
    }

    // MARK: Dependencies

    private let healthStore = HKHealthStore()
    private let ockStore: OCKStore
    private let recorder: DetectedMoodRecorder
    private let notifications: DetectionNotificationManager

    private var observerQuery: HKObserverQuery?
    private var isEvaluating = false

    var onUserConfirmedToast: ((String) -> Void)?
    /// Fired when the user confirms a mood spike from the notification.
    /// AppDelegate uses this to ask the Care view to scroll to & highlight the logMood card.
    var onPromptLogMood: (() -> Void)?

    private var state: PersistedState {
        didSet { Self.persist(state) }
    }

    init(
        ockStore: OCKStore,
        notifications: DetectionNotificationManager
    ) {
        self.ockStore = ockStore
        self.notifications = notifications
        self.recorder = DetectedMoodRecorder(store: ockStore)
        self.state = Self.loadPersisted() ?? PersistedState()
    }

    // MARK: Public lifecycle

    func start() async {
        Logger.detection.info("HeartRateAnomalyDetector.start() called")
        notifications.moodHandler = self

        guard HKHealthStore.isHealthDataAvailable() else {
            Logger.detection.warning("HealthKit unavailable on this device")
            return
        }

        let hrType = HKQuantityType(.heartRate)

        if let existing = observerQuery {
            healthStore.stop(existing)
            observerQuery = nil
        }

        do {
            try await healthStore.enableBackgroundDelivery(for: hrType, frequency: .immediate)
            Logger.detection.info("HR background delivery enabled")
        } catch {
            Logger.detection.error("HR enableBackgroundDelivery failed: \(error)")
        }

        observeAppForeground()

        let query = HKObserverQuery(sampleType: hrType, predicate: nil) { [weak self] _, completion, error in
            let safeCompletion = UncheckedSendableBox(completion)
            if let error {
                Logger.detection.error("HR observer query error: \(error)")
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

        await evaluate()
    }

    // MARK: Core evaluation

    private func evaluate() async {
        guard !isEvaluating else {
            Logger.detection.info("HR evaluate: skipping — already running")
            return
        }
        isEvaluating = true
        defer { isEvaluating = false }

        let onboarded = await Utility.checkIfOnboardingIsComplete()
        Logger.detection.info("HR evaluate: onboarded=\(onboarded), phase=\(self.state.phase.rawValue)")
        guard onboarded else { return }

        let now = Date()
        switch state.phase {
        case .idle:
            await evaluateIdle(now: now)
        case .pendingConfirmation:
            await evaluatePending(now: now)
        }
    }

    private func evaluateIdle(now: Date) async {
        if let last = state.lastDismissAt {
            let sinceDismiss = now.timeIntervalSince(last)
            if sinceDismiss < Self.dismissDebounce {
                let remaining = Int((Self.dismissDebounce - sinceDismiss) / 60)
                Logger.detection.info("HR Idle: debounced — \(remaining)min remaining (last dismiss \(last))")
                return
            }
        }

        let from = now.addingTimeInterval(-Self.hrDetectionWindow)
        let windowMin = Int(Self.hrDetectionWindow / 60)
        let hrAvg = await averageHeartRate(from: from, to: now)
        let hrSampleCount = await heartRateSampleCount(from: from, to: now)
        Logger.detection.info("HR Idle: avg HR in last \(windowMin)min = \(hrAvg) bpm (\(hrSampleCount) samples)")
        guard hrAvg > 0 else {
            Logger.detection.info("HR Idle: no HR samples in window — waiting")
            return
        }

        let restingHR = await restingHeartRateBaseline()
        let baseline = restingHR ?? Self.hrFallbackBaseline
        let baselineSource = restingHR != nil ? "restingHeartRate" : "fallback"
        let threshold = baseline + Self.hrSpikeDelta
        let delta = hrAvg - baseline
        Logger.detection.info(
            "HR Idle: baseline=\(baseline) (\(baselineSource)), threshold=\(threshold), delta=\(delta)"
        )
        guard hrAvg >= threshold else {
            Logger.detection.info("HR Idle: below threshold (\(hrAvg) < \(threshold)) — no trigger")
            return
        }

        let steps = await sumSteps(from: from, to: now)
        let suppressAt = Self.stepSuppressionThreshold
        Logger.detection.info(
            "HR Idle: spike candidate — steps in \(windowMin)min = \(steps), suppressAt = \(suppressAt)"
        )
        guard steps < Self.stepSuppressionThreshold else {
            Logger.detection.info("HR Idle: suppressed — user is moving (\(steps) steps)")
            return
        }

        if await userHasRecentRelatedActivity(now: now) {
            Logger.detection.info("HR Idle: suppressed — recent exercise/mood task outcome present")
            return
        }

        state.lastDetectedHR = hrAvg
        state.lastBaseline = baseline
        state.lastStepsInWindow = steps
        state.lastDetectedAt = now
        state.notificationPostedAt = now
        state.phase = .pendingConfirmation
        await notifications.postMoodSpikeNotification()
        Logger.detection.info(
            "HR TRIGGERED: posted prompt — hr=\(hrAvg) baseline=\(baseline) delta=\(delta) steps=\(steps)"
        )
    }

    private func evaluatePending(now: Date) async {
        guard let postedAt = state.notificationPostedAt else {
            Logger.detection.info("HR Pending: no notificationPostedAt — resetting")
            resetToIdle()
            return
        }
        let elapsed = now.timeIntervalSince(postedAt)
        Logger.detection.info(
            "HR Pending: \(Int(elapsed))s since prompt posted, timeout at \(Int(Self.unconfirmedTimeout))s"
        )
        guard elapsed >= Self.unconfirmedTimeout else { return }

        Logger.detection.info("HR Pending: timed out — writing unconfirmed record")
        await writeRecord(isUnconfirmed: true)
        notifications.cancelMoodSpikeNotification()
        state.lastDismissAt = Date()
        resetToIdle()
    }

    @discardableResult
    private func writeRecord(isUnconfirmed: Bool) async -> Bool {
        guard let detectedAt = state.lastDetectedAt,
              let hr = state.lastDetectedHR,
              let baseline = state.lastBaseline,
              let steps = state.lastStepsInWindow else {
            return false
        }
        do {
            try await recorder.record(
                detectedAt: detectedAt,
                hrAvg: hr,
                hrBaseline: baseline,
                stepsInWindow: steps,
                isUnconfirmed: isUnconfirmed
            )
            return true
        } catch {
            Logger.detection.error("Mood record write failed: \(error)")
            return false
        }
    }

    private func resetToIdle() {
        state.phase = .idle
        state.notificationPostedAt = nil
        state.lastDetectedHR = nil
        state.lastBaseline = nil
        state.lastStepsInWindow = nil
        state.lastDetectedAt = nil
    }

    private var _didRegisterForegroundObserver = false
    fileprivate var didRegisterForegroundObserver: Bool {
        get { _didRegisterForegroundObserver }
        set { _didRegisterForegroundObserver = newValue }
    }
}

// MARK: Queries

extension HeartRateAnomalyDetector {

    fileprivate func averageHeartRate(from: Date, to: Date) async -> Double {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let bpm = result?.averageQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: bpm)
            }
            healthStore.execute(query)
        }
    }

    /// Count of HR samples in window — useful for diagnosing why a spike isn't triggering.
    fileprivate func heartRateSampleCount(from: Date, to: Date) async -> Int {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: samples?.count ?? 0)
            }
            healthStore.execute(query)
        }
    }

    /// Most recent restingHeartRate sample (Apple Watch writes one/day). Nil if iPhone-only.
    fileprivate func restingHeartRateBaseline() async -> Double? {
        let type = HKQuantityType(.restingHeartRate)
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    fileprivate func sumSteps(from: Date, to: Date) async -> Double {
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

    fileprivate func userHasRecentRelatedActivity(now: Date) async -> Bool {
        // OCKOutcomeQuery.dateInterval filters by the task event's scheduled interval
        // for daily tasks the event covers the whole day
        // -> Query the full day, then filter by outcomt's actual createdDate to enforce
        // real suppression window
        let dayStart = Calendar.current.startOfDay(for: now)
        let windowStart = now.addingTimeInterval(-Self.activeTaskSuppressionWindow)
        var query = OCKOutcomeQuery(dateInterval: DateInterval(start: dayStart, end: now))
        query.taskIDs = (TaskID.exerciseRelated + TaskID.moodRelated)
            .filter { $0 != TaskID.detectedMoodSpike }
        do {
            let outcomes = try await ockStore.fetchOutcomes(query: query)
            let hasRecent = outcomes.contains { outcome in
                let outcomeCreated = outcome.createdDate ?? .distantPast
                let latestValue = outcome.values.map(\.createdDate).max() ?? .distantPast
                return max(outcomeCreated, latestValue) >= windowStart
            }
            return hasRecent
        } catch {
            Logger.detection.error("HR suppression outcome fetch failed: \(error)")
            return false
        }
    }

    fileprivate func observeAppForeground() {
        guard !didRegisterForegroundObserver else { return }
        didRegisterForegroundObserver = true
        let foregroundName = Notification.Name("UIApplicationWillEnterForegroundNotification")
        NotificationCenter.default.addObserver(
            forName: foregroundName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                Logger.detection.info("HR detector: willEnterForeground — re-running start()")
                await self?.start()
            }
        }
    }
}

// MARK: Persistence

extension HeartRateAnomalyDetector {

    fileprivate static let persistenceKey = "HeartRateAnomalyDetector.state"

    fileprivate static func loadPersisted() -> PersistedState? {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    fileprivate static func persist(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }
}

extension HeartRateAnomalyDetector: MoodNotificationHandler {

    func userConfirmedMoodSpike() async {
        Logger.detection.info("User confirmed mood spike (phase=\(self.state.phase.rawValue))")
        guard state.phase == .pendingConfirmation else { return }
        let ok = await writeRecord(isUnconfirmed: false)
        notifications.cancelMoodSpikeNotification()
        state.lastDismissAt = Date()
        resetToIdle()
        if ok {
            onUserConfirmedToast?(String(localized: "DETECTED_MOOD_TOAST_LOGGED"))
            onPromptLogMood?()
        }
    }

    func userDismissedMoodSpike() async {
        Logger.detection.info("User dismissed mood spike prompt")
        resetToIdle()
    }
}
