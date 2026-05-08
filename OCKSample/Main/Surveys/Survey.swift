//
//  Survey.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/3/24.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import Foundation
import CareKitStore

enum Survey: String, CaseIterable, Identifiable {
    var id: Self { self }
    case onboard      = "Onboard"
    case rangeOfMotion = "Range of Motion"
    case stroop       = "Stroop"

    func type() -> Surveyable {
        switch self {
        case .onboard:
            return Onboard()
        case .rangeOfMotion:
            return RangeOfMotion()
        case .stroop:
            return StroopTask()
        }
    }
}
