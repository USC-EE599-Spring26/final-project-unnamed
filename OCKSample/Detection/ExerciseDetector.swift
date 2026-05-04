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

/// Watches step data and prompts the user to log exercise when active without a task running.
///
/// Lifecycle:
///   1. `start()` registers an HKObserverQuery with background delivery.
///   2. Each wake-up runs `evaluate()` — checks the past 5 min of steps.
///   3. A state machine decides whether to prompt, wait for end, or idle.

/// Unsafe sendable wrapper for callbacks that Apple documents as thread-safe but don't conform to `@Sendable`
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
    /// Cool-down after a session is logged. Not applied on dismiss (false positive — no session to cool down from).
    private static let dismissDebounce: TimeInterval = 10 * 60
    /// If user never responds and movement ends, write unconfirmed record after this long.
    private static let unconfirmedTimeout: TimeInterval = 15 * 60
    /// Suppress trigger if any exercise-related task has an outcome within this window (user already logging manually).
    private static let activeTaskSuppressionWindow: TimeInterval = 20 * 60

    // MARK: State machine

    fileprivate enum Phase: String, Codable {
        case idle
        case pendingConfirmation     // start prompt posted, waiting on user
        case monitoringEnd           // user confirmed, waiting for movement to stop
        case pendingEndConfirmation  // end prompt posted, waiting on user
    }

    fileprivate struct PersistedState: Codable {
        var phase: Phase = .idle
        var sessionStart: Date?
        var notificationPostedAt: Date?
        var lastDismissAt: Date?
        // Prevents re-prompting too soon if user taps "still going" then drops below end threshold again.
        var endPromptPostedAt: Date?
    }

    /// Don't re-post the end prompt sooner than this after the user picked
    /// "still going" or after the previous end prompt fired.
    private static let endPromptDebounce: TimeInterval = 5 * 60

    // MARK: Dependencies

    private let healthStore = HKHealthStore()
    private let ockStore: OCKStore
    private let recorder: DetectedExerciseRecorder
    private let notifications: DetectionNotificationManager

    private var observerQuery: HKObserverQuery?
    /// Guards against multiple concurrent `evaluate()` runs when HK fires the
    /// observer query several times in quick succession. MainActor alone isn't
    /// enough — `await`s inside evaluate are reentrancy points.
    private var isEvaluating = false

    /// UI hook: transient toast on user actions (start-confirm, still going,
    /// ended). String is already localized.
    var onUserConfirmedToast: ((String) -> Void)?

    /// UI hook: fires whenever an active tracking session begins or ends so
    /// the in-app banner can show/hide. True while phase ∈
    /// {monitoringEnd, pendingEndConfirmation}.
    var onSessionActiveChanged: ((Bool) -> Void)?
    private var lastReportedActive = false
    private var state: PersistedState {
        didSet {
            Self.persist(state)
            reportSessionActiveIfChanged()
        }
    }

    private func reportSessionActiveIfChanged() {
        let active = state.phase == .monitoringEnd
            || state.phase == .pendingEndConfirmation
        guard active != lastReportedActive else { return }
        lastReportedActive = active
        onSessionActiveChanged?(active)
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

        // Persisted state may already represent an active session (e.g. user
        // killed the app mid-exercise). Sync the UI banner right away.
        reportSessionActiveIfChanged()

        guard HKHealthStore.isHealthDataAvailable() else {
            Logger.detection.warning("HealthKit unavailable on this device")
            return
        }

        // Auth is handled by onboarding's ORKRequestPermissionsStep — not here.
        // Unauthorized state just yields no samples; no crash.
        let stepType = HKQuantityType(.stepCount)

        // Tear down previous observer before re-registering.
        if let existing = observerQuery {
            healthStore.stop(existing)
            observerQuery = nil
        }

        // Background delivery → iOS wakes us when new samples arrive.
        do {
            try await healthStore.enableBackgroundDelivery(for: stepType, frequency: .immediate)
            Logger.detection.info("Background delivery enabled")
        } catch {
            Logger.detection.error("enableBackgroundDelivery failed: \(error)")
        }

        observeAppForeground()

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completion, error in
            // HKObserverQuery's completion isn't Sendable, but Apple documents it as thread-safe — wrap it to cross the async boundary.
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

        // Run once immediately; don't wait for the first HK update
        await evaluate()
    }

    // MARK: Core evaluation (runs on every wake-up)

    private func evaluate() async {
        guard !isEvaluating else {
            Logger.detection.info("evaluate: skipping — already running")
            return
        }
        isEvaluating = true
        defer { isEvaluating = false }

        // Skip until onboarding is complete — no notification/HealthKit permission yet
        let onboarded = await Utility.checkIfOnboardingIsComplete()
        let onboardOutcomes = await debugCountOnboardOutcomes()
        Logger.detection.info("evaluate: onboarded=\(onboarded), onboardOutcomes=\(onboardOutcomes)")
        guard onboarded else {
            return
        }

        let now = Date()
        switch state.phase {
        case .idle:
            await evaluateIdle(now: now)
        case .pendingConfirmation:
            await evaluatePending(now: now)
        case .monitoringEnd:
            await evaluateMonitoring(now: now)
        case .pendingEndConfirmation:
            await evaluateAwaitingEnd(now: now)
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
        // No after-session debounce here: user never engaged with the prompt,
        // so there was no real "session" to cool down from
        resetToIdle()
    }

    private func evaluateMonitoring(now: Date) async {
        // If we already posted an end prompt very recently, don't re-post —
        // user picked "Still going" and may briefly drop steps again.
        if let lastPost = state.endPromptPostedAt,
           now.timeIntervalSince(lastPost) < Self.endPromptDebounce {
            return
        }

        let recent = await sumSteps(from: now.addingTimeInterval(-Self.endWindow), to: now)
        let windowMin = Int(Self.endWindow / 60)
        let endThreshold = Self.stepEndedThreshold
        Logger.detection.info(
            "Monitoring: steps in last \(windowMin)min = \(recent), endThreshold = \(endThreshold)"
        )
        guard recent < Self.stepEndedThreshold else { return }

        Logger.detection.info("Monitoring: drop detected — posting end prompt")
        state.endPromptPostedAt = now
        state.phase = .pendingEndConfirmation
        await notifications.postExerciseEndedNotification()
    }

    private func evaluateAwaitingEnd(now: Date) async {
        // User never tapped Still/Ended. After the unconfirmed timeout,
        // write a record marked unconfirmed and reset.
        guard let postedAt = state.endPromptPostedAt else {
            resetToIdle()
            return
        }
        guard now.timeIntervalSince(postedAt) >= Self.unconfirmedTimeout else { return }

        let recent = await sumSteps(from: now.addingTimeInterval(-Self.endWindow), to: now)
        guard recent < Self.stepEndedThreshold else { return }

        Logger.detection.info("AwaitingEnd: timed out — writing unconfirmed record")
        await writeRecord(end: now, isUnconfirmed: true)
        notifications.cancelExerciseEndedNotification()
        state.lastDismissAt = Date()
        resetToIdle()
    }

    // MARK: DetectionNotificationHandler callbacks

    @discardableResult
    private func writeRecord(end: Date, isUnconfirmed: Bool) async -> Bool {
        guard let start = state.sessionStart else { return false }
        do {
            try await recorder.record(start: start, end: end, isUnconfirmed: isUnconfirmed)
            return true
        } catch {
            Logger.detection.error("Record write failed: \(error)")
            return false
        }
    }

    private func resetToIdle() {
        state.phase = .idle
        state.sessionStart = nil
        state.notificationPostedAt = nil
        state.endPromptPostedAt = nil
    }

    /// In-app card "Dismiss" — user says "this isn't real exercise, abort."
    /// No after-session debounce: a dismissed session never happened.
    func dismissActiveSession() async {
        Logger.detection.info("dismissActiveSession called (phase=\(self.state.phase.rawValue))")
        notifications.cancelAllDetectionNotifications()
        resetToIdle()
    }

    fileprivate var didRegisterForegroundObserver: Bool {
        get { _didRegisterForegroundObserver }
        set { _didRegisterForegroundObserver = newValue }
    }
    private var _didRegisterForegroundObserver = false
}

// MARK: Queries

extension ExerciseDetector {

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

    /// Walks backward from `endingAt` in 1-minute buckets and returns the
    /// timestamp of the first bucket where steps first became non-trivial.
    /// Capped at 30 minutes of lookback.
    fileprivate func estimatedMovementStart(endingAt: Date) async -> Date? {
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

    fileprivate func userIsAlreadyLoggingExercise(now: Date) async -> Bool {
        // OCKOutcomeQuery.dateInterval filters by the task event's scheduled interval — for daily tasks the event covers the whole day
        // -> Query the full day, then filter by outcomt's actual createdDate to enforce real suppression window
        let dayStart = Calendar.current.startOfDay(for: now)
        let windowStart = now.addingTimeInterval(-Self.activeTaskSuppressionWindow)
        var query = OCKOutcomeQuery(dateInterval: DateInterval(start: dayStart, end: now))
        query.taskIDs = TaskID.exerciseRelated.filter { $0 != TaskID.detectedExercise }
        do {
            let outcomes = try await ockStore.fetchOutcomes(query: query)
            let recent = outcomes.filter { outcome in
                let outcomeCreated = outcome.createdDate ?? .distantPast
                let latestValue = outcome.values.map(\.createdDate).max() ?? .distantPast
                return max(outcomeCreated, latestValue) >= windowStart
            }
            if !recent.isEmpty {
                Logger.detection.info("Found \(recent.count) recent exercise-related outcome(s) — suppressing")
            }
            return !recent.isEmpty
        } catch {
            Logger.detection.error("Outcome fetch for suppression failed: \(error)")
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
                Logger.detection.info("willEnterForeground — re-running start()")
                await self?.start()
            }
        }
    }

    fileprivate func debugCountOnboardOutcomes() async -> Int {
        var query = OCKOutcomeQuery()
        let dayStart = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        query.dateInterval = DateInterval(start: dayStart, end: Date().addingTimeInterval(86400))
        do {
            let all = try await ockStore.fetchAnyOutcomes(query: query)
            Logger.detection.info("All outcomes in store: \(all.count)")
            return all.count
        } catch {
            return -1
        }
    }
}

// MARK: Persistence

extension ExerciseDetector {

    fileprivate static let persistenceKey = "ExerciseDetector.state"

    fileprivate static func loadPersisted() -> PersistedState? {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    fileprivate static func persist(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }
}

extension ExerciseDetector: DetectionNotificationHandler {

    func userConfirmedDetectedExercise() async {
        Logger.detection.info("User confirmed. Current phase: \(self.state.phase.rawValue)")
        guard state.phase == .pendingConfirmation else { return }

        // Check whether movement already ended: if so, write immediately using
        // a best-effort end time (now). Otherwise enter monitoring.
        let now = Date()
        let recent = await sumSteps(from: now.addingTimeInterval(-Self.endWindow), to: now)
        Logger.detection.info("Confirm: recent steps = \(recent), threshold = \(Self.stepEndedThreshold)")
        if recent < Self.stepEndedThreshold {
            Logger.detection.info("Movement already ended — writing record immediately")
            let ok = await writeRecord(end: now, isUnconfirmed: false)
            state.lastDismissAt = Date()
            resetToIdle()
            if ok {
                onUserConfirmedToast?(String(localized: "DETECTED_EXERCISE_TOAST_LOGGED"))
            }
        } else {
            Logger.detection.info("Movement ongoing — entering monitoringEnd phase")
            state.phase = .monitoringEnd
            state.notificationPostedAt = nil
            onUserConfirmedToast?(String(localized: "DETECTED_EXERCISE_TOAST_TRACKING"))
        }
    }

    func userDismissedDetectedExercise() async {
        Logger.detection.info("User dismissed start notification")
        resetToIdle()
    }

    func userIndicatedStillExercising() async {
        Logger.detection.info("User picked 'still going' (phase=\(self.state.phase.rawValue))")
        guard state.phase == .pendingEndConfirmation else { return }
        state.phase = .monitoringEnd
        // endPromptPostedAt stays — used as the 5-min repost debounce.
        onUserConfirmedToast?(String(localized: "DETECTED_EXERCISE_TOAST_STILL"))
    }

    func userConfirmedExerciseEnded() async {
        Logger.detection.info("User confirmed end (phase=\(self.state.phase.rawValue))")
        guard state.phase == .pendingEndConfirmation else { return }
        let now = Date()
        let ok = await writeRecord(end: now, isUnconfirmed: false)
        notifications.cancelExerciseEndedNotification()
        state.lastDismissAt = Date()
        resetToIdle()
        if ok {
            onUserConfirmedToast?(String(localized: "DETECTED_EXERCISE_TOAST_LOGGED"))
        }
    }
}
