//
//  OCKTask+ResearchKitSwiftUI.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/3/24.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import Foundation

extension OCKTask {
    var uiKitSurvey: Survey? {
        get {
            guard let surveyInfo = userInfo?[Constants.uiKitSurvey],
                  let surveyType = Survey(rawValue: surveyInfo) else {
                return nil
            }
            return surveyType // Saved survey type
        }
        set {
            if userInfo == nil {
                // Initialize userInfo with empty dictionary
                userInfo = .init()
            }
            // Set the new card type
            userInfo?[Constants.uiKitSurvey] = newValue?.rawValue
        }
    }
}
