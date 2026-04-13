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
    static let qualityOfLife = "qualityOfLife"

    // Behavioral tracking
    static let logFocus = "log_focus"
    static let logDistraction = "log_distraction"
    static let logMood = "log_mood"
    static let logStress = "log_stress"
    static let logSleep = "log_sleep"
    static let logMedication = "log_medication"

    // Adaptive feedback
    static let refocusPrompt = "refocus_prompt"
    static let breathingExercise = "breathing_exercise"
    static let takeBreak = "take_break"
    static let movePrompt = "move_prompt"
    static let microCheckin = "micro_checkin"

    // Clinical assessment
    static let inattentionSurvey = "inattention_survey"
    static let hyperactivitySurvey = "hyperactivity_survey"
    static let impulsivitySurvey = "impulsivity_survey"
    static let weeklyReflection = "weekly_reflection"

    // HealthKitTask
    static let steps = "steps"
    static let stress = "stress"
    static let attention = "attention"
    static let routine = "routine"

    static var ordered: [String] {
        orderedObjective + orderedSubjective
    }

    static var orderedObjective: [String] {
        [
            Self.steps,
            Self.stress,
            Self.attention,
            Self.routine
        ]
    }

    static var orderedSubjective: [String] {
        [
            Self.methylphenidate,
            Self.cardios,
            Self.stretch,
            Self.inattention,
            Self.logFocus,
            Self.logDistraction,
            Self.logMood,
            Self.logSleep,
            Self.refocusPrompt,
            Self.breathingExercise,
            Self.takeBreak,
            Self.weeklyReflection
        ]
    }

    static var orderedWatchOS: [String] {
        [
            Self.methylphenidate,
            Self.cardios,
            Self.stretch
        ]
    }
}
