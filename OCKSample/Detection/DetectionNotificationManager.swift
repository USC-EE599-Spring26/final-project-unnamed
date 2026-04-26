//
//  DetectionNotificationManager.swift
//  OCKSample
//
//  Created by Student on 4/23/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import Foundation
import UserNotifications
import os.log

/// Callback interface the detector implements so the notification manager can
/// report user decisions without importing the detector directly.
@MainActor
protocol DetectionNotificationHandler: AnyObject {
    func userConfirmedDetectedExercise() async
    func userDismissedDetectedExercise() async
    func userIndicatedStillExercising() async
    func userConfirmedExerciseEnded() async
}

/// Owns notification authorization, category registration, and tap routing for
/// auto-detected activity prompts. One instance lives on AppDelegate.
@MainActor
final class DetectionNotificationManager: NSObject {

    enum Identifier {
        // Stage 1 — "Are you exercising?"
        static let category = "detected_exercise.category"
        static let notification = "detected_exercise.prompt"
        static let actionLog = "detected_exercise.action.log"
        static let actionDismiss = "detected_exercise.action.dismiss"
        // Stage 2 — "Did you finish?"
        static let endCategory = "detected_exercise.end.category"
        static let endNotification = "detected_exercise.end.prompt"
        static let actionStill = "detected_exercise.action.still"
        static let actionEnded = "detected_exercise.action.ended"
    }

    weak var handler: DetectionNotificationHandler?

    private let center = UNUserNotificationCenter.current()

    /// Call once at app launch. Registers the category (safe even before the
    /// user grants permission) and becomes the delegate so tap actions route
    /// back to us.
    func configure() {
        center.delegate = self
        center.setNotificationCategories([
            Self.buildStartCategory(),
            Self.buildEndCategory()
        ])
    }

    /// Request notification permission. Logs current status so we can diagnose
    /// cases where the system alert never appears (usually: already decided).
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        Logger.detection.info("Notification auth status: \(settings.authorizationStatus.rawValue)")
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            Logger.detection.info("Notification auth granted=\(granted)")
        } catch {
            Logger.detection.error("Notification auth request failed: \(error)")
        }
    }

    /// Post the "are you exercising?" prompt.
    func postExerciseDetectedNotification() async {
        let settings = await center.notificationSettings()
        // swiftlint:disable:next line_length
        Logger.detection.info("Posting prompt. Auth status: \(settings.authorizationStatus.rawValue), alertSetting: \(settings.alertSetting.rawValue)")

        let content = UNMutableNotificationContent()
        content.title = String(localized: "DETECTED_EXERCISE_NOTIF_TITLE")
        content.body = String(localized: "DETECTED_EXERCISE_NOTIF_BODY")
        content.categoryIdentifier = Identifier.category
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Identifier.notification,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            Logger.detection.info("Notification request added successfully")
        } catch {
            Logger.detection.error("Failed to post detection notification: \(error)")
        }
    }

    /// Post the stage-2 "did you finish?" prompt.
    func postExerciseEndedNotification() async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "DETECTED_EXERCISE_END_NOTIF_TITLE")
        content.body = String(localized: "DETECTED_EXERCISE_END_NOTIF_BODY")
        content.categoryIdentifier = Identifier.endCategory
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Identifier.endNotification,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            Logger.detection.info("End notification posted")
        } catch {
            Logger.detection.error("Failed to post end notification: \(error)")
        }
    }

    /// Remove pending/delivered start prompts.
    func cancelExerciseDetectedNotification() {
        let ids = [Identifier.notification]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Remove pending/delivered end prompts.
    func cancelExerciseEndedNotification() {
        let ids = [Identifier.endNotification]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Cancel both prompts at once (used when user dismisses via in-app card).
    func cancelAllDetectionNotifications() {
        cancelExerciseDetectedNotification()
        cancelExerciseEndedNotification()
    }

    private static func buildStartCategory() -> UNNotificationCategory {
        let log = UNNotificationAction(
            identifier: Identifier.actionLog,
            title: String(localized: "DETECTED_EXERCISE_ACTION_LOG"),
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: Identifier.actionDismiss,
            title: String(localized: "DETECTED_EXERCISE_ACTION_DISMISS"),
            options: [.destructive]
        )
        return UNNotificationCategory(
            identifier: Identifier.category,
            actions: [log, dismiss],
            intentIdentifiers: [],
            options: []
        )
    }

    private static func buildEndCategory() -> UNNotificationCategory {
        let still = UNNotificationAction(
            identifier: Identifier.actionStill,
            title: String(localized: "DETECTED_EXERCISE_END_ACTION_STILL"),
            options: []
        )
        let ended = UNNotificationAction(
            identifier: Identifier.actionEnded,
            title: String(localized: "DETECTED_EXERCISE_END_ACTION_ENDED"),
            options: [.foreground]
        )
        return UNNotificationCategory(
            identifier: Identifier.endCategory,
            actions: [still, ended],
            intentIdentifiers: [],
            options: []
        )
    }
}

extension DetectionNotificationManager: UNUserNotificationCenterDelegate {

    // Show the banner even when app is foregrounded — useful during testing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionID = response.actionIdentifier
        let categoryID = response.notification.request.content.categoryIdentifier
        Logger.detection.info("didReceive action: \(actionID) (category=\(categoryID))")
        let done = UncheckedSendableCompletion(completionHandler)
        Task { @MainActor [weak self] in
            guard let self else { done.value(); return }
            Logger.detection.info("handler present: \(self.handler != nil)")
            switch (categoryID, actionID) {
            // Stage 1 — start prompt
            case (Identifier.category, Identifier.actionLog),
                 (Identifier.category, UNNotificationDefaultActionIdentifier):
                await self.handler?.userConfirmedDetectedExercise()
            case (Identifier.category, Identifier.actionDismiss),
                 (Identifier.category, UNNotificationDismissActionIdentifier):
                await self.handler?.userDismissedDetectedExercise()
            // Stage 2 — end prompt
            case (Identifier.endCategory, Identifier.actionStill):
                await self.handler?.userIndicatedStillExercising()
            case (Identifier.endCategory, Identifier.actionEnded),
                 (Identifier.endCategory, UNNotificationDefaultActionIdentifier):
                await self.handler?.userConfirmedExerciseEnded()
            default:
                break
            }
            done.value()
        }
    }
}

private struct UncheckedSendableCompletion: @unchecked Sendable {
    let value: () -> Void
    init(_ value: @escaping () -> Void) { self.value = value }
}
