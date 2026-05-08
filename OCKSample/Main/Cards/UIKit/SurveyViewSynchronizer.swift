//
//  SurveyViewSynchronizer.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/3/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

#if canImport(ResearchKit) && canImport(ResearchKitUI)

import CareKit
import CareKitStore
import CareKitUI
import ResearchKit
import ResearchKitActiveTask
import ResearchKitUI
import UIKit
import os.log

final class SurveyViewSynchronizer: OCKSurveyTaskViewSynchronizer {

    override func updateView(
        _ view: OCKInstructionsTaskView,
        context: OCKSynchronizationContext<OCKTaskEvents>
    ) {

        super.updateView(view, context: context)

        let isHidden: Bool
        let textUpdate: TextUpdate

        if let event = context.viewModel.first?.first, event.outcome != nil {
            isHidden = false
            if let task = event.task as? OCKTask {
                switch task.id {
                case Onboard.identifier():
                    textUpdate = .set("Welcome to PulseBuddy.")
                case RangeOfMotion.identifier():
                    let range: Double = event.answer(kind: "range")
                    textUpdate = .set("Your Range of Motion Result: \(range)")
                case StroopTask.identifier():
                    textUpdate = .set(StroopTask().displayText(for: event))
                default:
                    textUpdate = .keep
                }
            } else {
                textUpdate = .set(nil)
            }
        } else {
            isHidden = true
            textUpdate = .keep
        }

        MainActor.assumeIsolated {
            view.instructionsLabel.isHidden = isHidden
            if case .set(let text) = textUpdate {
                view.instructionsLabel.text = text
            }
        }
    }

    private enum TextUpdate {
        case keep
        case set(String?)
    }
}

#endif // canImport(ResearchKit) && canImport(ResearchKitUI)
