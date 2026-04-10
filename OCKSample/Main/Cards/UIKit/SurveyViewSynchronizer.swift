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

            guard let task = event.task as? OCKTask else {
                view.instructionsLabel.text = nil
                return
            }

            switch task.id {
            case Onboard.identifier():
                view.instructionsLabel.text = "Welcome to PulseBuddy."
            case RangeOfMotion.identifier():
                let range: Double = event.answer(kind: "range")
                view.instructionsLabel.text = "Your Range of Motion Result: \(range)"
            default:
                view.instructionsLabel.isHidden = false
            }

            guard let task = event.task as? OCKTask else {
                view.instructionsLabel.text = nil
                return
            }
        } else {
            DispatchQueue.main.async {
                view.instructionsLabel.isHidden = true
            }
        }
    }
}

#endif
