//
//  StroopTask.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/29.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
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
        return ORKOrderedTask.reactionTime(
            withIdentifier: StroopTask.identifier(),
            intendedUseDescription: "Measures how quickly you respond — reaction speed is a key ADHD indicator.",
            maximumStimulusInterval: 8,
            minimumStimulusInterval: 4,
            thresholdAcceleration: 0.5,
            numberOfAttempts: 10,
            timeout: 10,
            successSound: 1117,
            timeoutSound: 1050,
            failureSound: 1053,
            options: []
        )
    }

    // MARK: - Extract answers

    func extractAnswers(_ result: ORKTaskResult) -> [OCKOutcomeValue]? {
        let reactionResults = result.results?
            .compactMap { $0 as? ORKStepResult }
            .compactMap { $0.results }
            .flatMap { $0 }
            .compactMap { $0 as? ORKReactionTimeResult } ?? []

        guard !reactionResults.isEmpty else {
            assertionFailure("StroopTask: failed to parse ORKReactionTimeResult")
            return nil
        }

        let times   = reactionResults.map { $0.timestamp }
        let total   = times.reduce(0.0, +)
        let avgTime = total / Double(times.count)

        var value = OCKOutcomeValue(avgTime)
        value.kind = "reactionTime"
        return [value]
    }

    // MARK: - Display text (shown on card after completion)

    func displayText(for event: OCKAnyEvent) -> String {
        let avg: Double = event.answer(kind: "reactionTime")
        return String(format: "Avg reaction time: %.3f s", avg)
    }
}
#endif
