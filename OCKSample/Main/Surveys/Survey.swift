//
//  Survey.swift
//  OCKSample
//
//  Created by Student on 4/7/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//


import Foundation
import CareKitStore

enum Survey: String, CaseIterable, Identifiable {
    var id: Self { self }
    case onboard = "Onboard"
    case rangeOfMotion = "Range of Motion"

    func type() -> Surveyable {
        switch self {
        case .onboard:
            return Onboard()
        case .rangeOfMotion:
            return RangeOfMotion()
        }
    }
}
