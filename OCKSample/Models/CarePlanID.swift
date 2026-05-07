//
//  CarePlanID.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/3/24.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import Foundation

enum CarePlanID: String, CaseIterable, Identifiable {
    var id: Self { self }
    case health // Add custom id's for your Care Plans, these are examples
    case wellness
    case nutrition
    case behavioralTracking
    case adaptiveFeedback
    case clinicalAssessment
    case custom
}
