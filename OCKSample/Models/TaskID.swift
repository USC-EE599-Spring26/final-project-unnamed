//
//  TaskID.swift
//  OCKSample
//
//  Created by Corey Baker on 4/14/23.
//  Copyright © 2023 Network Reconnaissance Lab. All rights reserved.
//

import Foundation

enum TaskID {
    static let methylphenidate = "methylphenidate"
    static let inattention = "inattention"
    static let stretch = "stretch"
    static let cardios = "cardios"
    static let steps = "steps"
    static let ovulationTestResult = "ovulationTestResult"
    static let qualityOfLife = "qualityOfLife"

    static var ordered: [String] {
        orderedObjective + orderedSubjective
    }

    static var orderedObjective: [String] {
        [ Self.steps/*, Self.ovulationTestResult*/ ]
    }

    static var orderedSubjective: [String] {
        [ Self.methylphenidate, Self.cardios, Self.stretch, Self.inattention]
    }

    static var orderedWatchOS: [String] {
        [ Self.methylphenidate, Self.cardios, Self.stretch ]
    }
}
