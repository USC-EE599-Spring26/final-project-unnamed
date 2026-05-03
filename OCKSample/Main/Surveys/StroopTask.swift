//
//  StroopTask.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/29.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//
//  ResearchKit active task — Stroop cognitive interference test.
//  Measures focused attention and cognitive flexibility by asking the user
//  to tap the COLOR of a word, not the word itself.
//

import CareKitStore
import UIKit
#if canImport(ResearchKit) && canImport(ResearchKitUI)
import ResearchKit
import ResearchKitActiveTask
import ResearchKitUI
#endif

struct StroopTask: Surveyable {
    static var surveyType: Survey { Survey.stroop }
}

#if canImport(ResearchKit) && canImport(ResearchKitUI)
extension StroopTask {

    // MARK: - Create survey

    func createSurvey() -> ORKTask {
        return ORKOrderedTask.stroopTask(
            withIdentifier: StroopTask.identifier(),
            intendedUseDescription: "Tap the color of the word.",
            numberOfAttempts: 20,
            options: []
        )
    }

    // MARK: - Extract answers

    /// Saves two outcome values:
    /// - `"accuracy"` — percentage of correct color taps (0–100)
    /// - `"responseTime"` — average response time in seconds
    func extractAnswers(_ result: ORKTaskResult) -> [OCKOutcomeValue]? {
        let stroopResults = result.results?
            .compactMap { $0 as? ORKStepResult }
            .compactMap { $0.results }
            .flatMap { $0 }
            .compactMap { $0 as? ORKStroopResult } ?? []

        guard !stroopResults.isEmpty else {
            assertionFailure("StroopTask: failed to parse ORKStroopResult")
            return nil
        }

        let total    = stroopResults.count
        let correct  = stroopResults.filter { $0.color == $0.colorSelected }.count
        let accuracy = Double(correct) / Double(total) * 100.0

        let times   = stroopResults.map { $0.endTime - $0.startTime }
        let avgTime = times.reduce(0.0, +) / Double(total)

        var accuracyValue = OCKOutcomeValue(accuracy)
        accuracyValue.kind = "accuracy"

        var responseTimeValue = OCKOutcomeValue(avgTime)
        responseTimeValue.kind = "responseTime"

        return [accuracyValue, responseTimeValue]
    }

    // MARK: - Display text (shown on card after completion)

    func displayText(for event: OCKAnyEvent) -> String {
        let accuracy: Double = event.answer(kind: "accuracy")
        let responseTime: Double = event.answer(kind: "responseTime")
        return String(format: "Accuracy: %.0f%%  · Avg response: %.2f s", accuracy, responseTime)
    }
}
#endif
