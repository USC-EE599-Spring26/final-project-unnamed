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
}

/// Owns notification authorization, category registration, and tap routing for
/// auto-detected activity prompts. One instance lives on AppDelegate.
@MainActor
final class DetectionNotificationManager: NSObject {

    enum Identifier {
        static let category = "detected_exercise.category"
        static let notification = "detected_exercise.prompt"
        static let actionLog = "detected_exercise.action.log"
        static let actionDismiss = "detected_exercise.action.dismiss"
    }

    weak var handler: DetectionNotificationHandler?

    private let center = UNUserNotificationCenter.current()

    /// Call once at app launch. Registers the category (safe even before the
    /// user grants permission) and becomes the delegate so tap actions route
    /// back to us.
    func configure() {
        center.delegate = self
        center.setNotificationCategories([Self.buildCategory()])
    }

    /// Request notification permission. Silently no-ops if already decided.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Logger.detection.error("Notification auth request failed: \(error)")
        }
    }

    /// Post the "are you exercising?" prompt.
    func postExerciseDetectedNotification() async {
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
        } catch {
            Logger.detection.error("Failed to post detection notification: \(error)")
        }
    }

    /// Remove a pending/delivered detection prompt (e.g. movement ended before
    /// the user responded — we don't want a stale notification sitting around).
    func cancelExerciseDetectedNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.notification])
        center.removeDeliveredNotifications(withIdentifiers: [Identifier.notification])
    }

    private static func buildCategory() -> UNNotificationCategory {
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
}

extension DetectionNotificationManager: UNUserNotificationCenterDelegate {

    // Show the banner even when app is foregrounded — useful during testing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        await MainActor.run {
            switch actionID {
            case Identifier.actionLog, UNNotificationDefaultActionIdentifier:
                // Default action = user tapped the notification body itself.
                // Treat as confirmation.
                Task { await self.handler?.userConfirmedDetectedExercise() }
            case Identifier.actionDismiss, UNNotificationDismissActionIdentifier:
                Task { await self.handler?.userDismissedDetectedExercise() }
            default:
                break
            }
        }
    }
}
