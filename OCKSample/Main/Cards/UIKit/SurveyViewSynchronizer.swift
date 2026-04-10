//
//  SurveyViewSynchronizer.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/3/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

#if canImport(ResearchKit)

import CareKit
import CareKitStore
import CareKitUI
import ResearchKit
import UIKit
import os.log

final class SurveyViewSynchronizer: OCKSurveyTaskViewSynchronizer {

    override func updateView(
        _ view: OCKInstructionsTaskView,
        context: OCKSynchronizationContext<OCKTaskEvents>
    ) {

        super.updateView(view, context: context)

        if let event = context.viewModel.first?.first, event.outcome != nil {
            view.instructionsLabel.isHidden = false
            /*
             TODOx: You need to modify this so the instuction label shows
             correctly for each Task/Card.
             Hint - Each event (OCKAnyEvent) has a task. How can you use
             this task to determine what instruction answers should show?
             Look at how the CareViewController differentiates between
             surveys.
             */
            /*let pain = event.answer(kind: RangeOfMotion.)
            let sleep = event.answer(kind: CheckIn.sleepItemIdentifier)

            view.instructionsLabel.text = """
                Pain: \(Int(pain))
                Sleep: \(Int(sleep)) hours
                """
             */
            guard
                let task = event.task as? OCKTask,
                let survey = task.uiKitSurvey
            else {
                view.instructionsLabel.text = "Completed"
                return
            }
            // Each uiKitSurvey type knows its own answer identifiers.
            // Delegate display logic back to the survey type itself.
            let surveyType = survey.type()
            view.instructionsLabel.text = surveyType.displayText(for: event)

        } else {
            view.instructionsLabel.isHidden = true
        }
    }
}

#endif
