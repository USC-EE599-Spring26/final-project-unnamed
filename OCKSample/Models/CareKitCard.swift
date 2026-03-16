//
//  CareKitCard.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/2/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import Foundation

enum CareKitCard: String, CaseIterable, Identifiable {
    var id: Self { self }

    case button = "Button"
    case checklist = "Checklist"
    case featured = "Featured"
    case grid = "Grid"
    case instruction = "Instruction"
    case labeledValue = "Labeled Value"
    case link = "Link"
    case numericProgress = "Numeric Progress"
    case simple = "Simple"
    case survey = "Survey"
    case custom = "Custom"

}

enum CareKitAsset: String, CaseIterable, Identifiable {

    case walk = "figure.walk"
    case run = "figure.run"
    case cycle = "figure.outdoor.cycle"
    case yoga = "figure.yoga"
    case stretch = "figure.cooldown"
    case stairs = "figure.stairs"

    case pill = "pill.fill"
    case pills = "pills.fill"
    case heart = "heart.fill"
    case cardio = "heart.text.square.fill"
    case lung = "lungs.fill"
    case brain = "brain.head.profile"
    case blood = "drop.fill"
    case thermometer = "thermometer.medium"

    case water = "cup.and.saucer.fill"
    case sleep = "moon.stars.fill"
    case nutrition = "apple.logo"
    case weight = "scale.3d"

    case check = "checkmark.circle.fill"
    case alert = "exclamationmark.triangle.fill"
    case phone = "phone.bubble.left.fill"
    case message = "message.fill"
    case info = "info.circle.fill"
    case dots = "circle.dotted"

    var id: String { self.rawValue }

    var displayName: String {
        return self.rawValue
            .replacingOccurrences(of: "figure.", with: "")
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
            .capitalized
    }
}
