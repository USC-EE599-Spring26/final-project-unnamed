//
//  UserType.swift
//  OCKSample
//
//  Created by Corey Baker on 4/14/23.
//  Copyright © 2023 Network Reconnaissance Lab. All rights reserved.
//

import Foundation

enum UserType: String, Codable, CaseIterable, Identifiable {
    var id: Self { self }

    case patient    = "Patient"
    case clinician  = "Clinician"
    case none       = "None"

    var displayName: String {
        switch self {
        case .patient: return "Patient"
        case .clinician:  return "Clinician"
        case .none:    return "None"
        }
    }

    var systemImage: String {
        switch self {
        case .patient: return "person.fill"
        case .clinician:  return "stethoscope"
        case .none:    return "questionmark"
        }
    }
}
