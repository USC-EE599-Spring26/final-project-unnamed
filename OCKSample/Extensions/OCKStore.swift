//
//  OCKStore.swift
//  OCKSample
//
//  Created by Corey Baker on 1/5/22.
//  Copyright © 2022 Network Reconnaissance Lab. All rights reserved.
//

import Foundation
import CareKitEssentials
import CareKitStore
import Contacts
import os.log
import ParseSwift
import ParseCareKit
#if os(iOS)
import ResearchKitSwiftUI
#endif

extension OCKStore {

    @MainActor
    class func getCarePlanUUIDs() async throws -> [CarePlanID: UUID] {
        var results = [CarePlanID: UUID]()

        guard let store = AppDelegateKey.defaultValue?.store else {
            return results
        }

        var query = OCKCarePlanQuery(for: Date())
        query.ids = CarePlanID.allCases.map(\.rawValue)

        let foundCarePlans = try await store.fetchCarePlans(query: query)
        // Populate the dictionary for all CarePlan's
        CarePlanID.allCases.forEach { carePlanID in
            results[carePlanID] = foundCarePlans
                .first(where: { $0.id == carePlanID.rawValue })?.uuid
        }
        return results
    }

    @MainActor
    func fetchAllCarePlans() async -> [OCKCarePlan] {
        let query = OCKCarePlanQuery(for: Date())
        return (try? await fetchCarePlans(query: query)) ?? []
    }

    /**
     Adds an `OCKAnyCarePlan`*asynchronously*  to `OCKStore` if it has not been added already.

     - parameter carePlans: The array of `OCKAnyCarePlan`'s to be added to the `OCKStore`.
     - parameter patientUUID: The uuid of the `OCKPatient` to tie to the `OCKCarePlan`. Defaults to nil.
     - throws: An error if there was a problem adding the missing `OCKAnyCarePlan`'s.
     - note: `OCKAnyCarePlan`'s that have an existing `id` will not be added and will not cause errors to be thrown.
    */
    func addCarePlansIfNotPresent(
        _ carePlans: [OCKAnyCarePlan],
        patientUUID: UUID? = nil
    ) async throws {
        let carePlanIdsToAdd = carePlans.compactMap { $0.id }

        // Prepare query to see if Care Plan are already added
        var query = OCKCarePlanQuery(for: Date())
        query.ids = carePlanIdsToAdd
        let foundCarePlans = try await self.fetchAnyCarePlans(query: query)
        let foundCarePlanIDs = Set(foundCarePlans.compactMap { $0.id })

        // Check results to see if there's a missing Care Plan
        let carePlanNotInStore: [OCKAnyCarePlan] = carePlans.compactMap { potentialCarePlan in
            guard !foundCarePlanIDs.contains(potentialCarePlan.id) else {
                return nil
            }

            guard var mutableCarePlan = potentialCarePlan as? OCKCarePlan else {
                return potentialCarePlan
            }

            mutableCarePlan.patientUUID = patientUUID
            // TODOx: Add CarePlans specific to your app here.
            return mutableCarePlan
        }

        // Only add if there's a new Care Plan
        if carePlanNotInStore.count > 0 {
            do {
                _ = try await self.addAnyCarePlans(carePlanNotInStore)
                Logger.ockStore.info("Added Care Plans into OCKStore!")
            } catch {
                Logger.ockStore.error("Error adding Care Plans: \(error.localizedDescription)")
            }
        }
    }

    func addContactsIfNotPresent(_ contacts: [OCKContact]) async throws -> [OCKContact] {
        let contactIdsToAdd = contacts.compactMap { $0.id }

        // Prepare query to see if contacts are already added
        var query = OCKContactQuery(for: Date())
        query.ids = contactIdsToAdd

        let foundContacts = try await fetchContacts(query: query)
        let foundContactIDs = Set(foundContacts.map(\.id))

        // Find all missing tasks.
        let contactsNotInStore = contacts.filter { !foundContactIDs.contains($0.id) }

        // Only add if there's a new task
        guard contactsNotInStore.count > 0 else {
            return []
        }

        let addedContacts = try await addContacts(contactsNotInStore)
        return addedContacts
    }

    /// Idempotent sync point for auto-detection tasks (`detectedExercise`,
    /// `detectedMoodSpike`). Called on every app launch so users whose store
    /// was created before a new detection task was introduced still get it
    /// added without resetting their account.
    ///
    /// Why a separate method rather than relying on `populateDefault…`:
    /// `populateDefault…` only runs on signup / specific onboarding paths.
    /// Already-logged-in users wouldn't pick up newly-added detection tasks
    /// without this sync hook.
    func syncDetectionTasks() async throws {
        let carePlanUUIDs = try await Self.getCarePlanUUIDs()

        let allDay = OCKScheduleElement(
            start: Calendar.current.startOfDay(for: Date()), end: nil,
            interval: DateComponents(day: 1),
            text: nil, targetValues: [], duration: .allDay
        )
        let dailySchedule = OCKSchedule(composing: [allDay])

        var detectedExercise = OCKTask(
            id: TaskID.detectedExercise,
            title: String(localized: "DETECTED_EXERCISE"),
            carePlanUUID: carePlanUUIDs[.wellness],
            schedule: dailySchedule
        )
        detectedExercise.impactsAdherence = false
        detectedExercise.asset = "figure.walk.motion"
        detectedExercise.card = .simple
        detectedExercise.priority = 20

        var detectedMoodSpike = OCKTask(
            id: TaskID.detectedMoodSpike,
            title: String(localized: "DETECTED_MOOD_SPIKE"),
            carePlanUUID: carePlanUUIDs[.wellness],
            schedule: dailySchedule
        )
        detectedMoodSpike.impactsAdherence = false
        detectedMoodSpike.asset = "heart.text.square"
        detectedMoodSpike.card = .simple
        detectedMoodSpike.priority = 21

        let added = try await addTasksIfNotPresent([detectedExercise, detectedMoodSpike])
        if !added.isEmpty {
            Logger.detection.info("syncDetectionTasks: added \(added.map(\.id))")
        }
    }

    func populateCarePlans(patientUUID: UUID? = nil) async throws {
        let healthCarePlan = OCKCarePlan(
            id: CarePlanID.health.rawValue,
            title: "Health Care Plan",
            patientUUID: patientUUID
        )
        let wellnessCarePlan = OCKCarePlan(
            id: CarePlanID.wellness.rawValue,
            title: "Wellness",
            patientUUID: patientUUID
        )
        let nutritionCarePlan = OCKCarePlan(
            id: CarePlanID.nutrition.rawValue,
            title: "Nutrition",
            patientUUID: patientUUID
        )
        let behavioralCarePlan = OCKCarePlan(
            id: CarePlanID.behavioralTracking.rawValue,
            title: "Behavioral Tracking",
            patientUUID: patientUUID
        )
        let feedbackCarePlan = OCKCarePlan(
            id: CarePlanID.adaptiveFeedback.rawValue,
            title: "Adaptive Feedback",
            patientUUID: patientUUID
        )
        let clinicalAssessmentCarePlan = OCKCarePlan(
            id: CarePlanID.clinicalAssessment.rawValue,
            title: "Clinical Assessment",
            patientUUID: patientUUID
        )
        let customCarePlan = OCKCarePlan(
            id: CarePlanID.custom.rawValue,
            title: "Custom",
            patientUUID: patientUUID
        )
        try await addCarePlansIfNotPresent(
            [
                healthCarePlan,
                wellnessCarePlan,
                nutritionCarePlan,
                behavioralCarePlan,
                feedbackCarePlan,
                clinicalAssessmentCarePlan,
                customCarePlan
            ],
            patientUUID: patientUUID
        )
    }

    // Adds tasks and contacts into the store
    func populateDefaultCarePlansTasksContacts(
        _ patientUUID: UUID? = nil,
        startDate: Date = Date()
	) async throws {

        try await populateCarePlans(patientUUID: patientUUID)

        let carePlanUUIDs = try await Self.getCarePlanUUIDs()

        let thisMorning = Calendar.current.startOfDay(for: startDate)
        let aFewDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: thisMorning)!
        let beforeBreakfast = Calendar.current.date(byAdding: .hour, value: 8, to: aFewDaysAgo)!
        let afterLunch = Calendar.current.date(byAdding: .hour, value: 14, to: aFewDaysAgo)!
        let evening = Calendar.current.date(byAdding: .hour, value: 20, to: aFewDaysAgo)!

        let schedule = OCKSchedule(
            composing: [
                OCKScheduleElement(start: beforeBreakfast, end: nil, interval: DateComponents(day: 1)),
                OCKScheduleElement(start: afterLunch, end: nil, interval: DateComponents(day: 2))
            ]
        )

        var methylphenidate = OCKTask(
            id: TaskID.methylphenidate,
            title: String(localized: "TAKE_METHYLPHENIDATE"),
            carePlanUUID: carePlanUUIDs[.health],
            schedule: schedule
        )
        methylphenidate.instructions = String(localized: "METHYLPHENIDATE_INSTRUCTIONS")
        methylphenidate.asset = "pills.fill"
        methylphenidate.card = .checklist
        methylphenidate.priority = 5
        methylphenidate.carePlanUUID = carePlanUUIDs[.health]

        let cardioSchedule = OCKSchedule(composing: [
            OCKScheduleElement(start: beforeBreakfast, end: nil, interval: DateComponents(day: 2))
        ])
        var cardios = OCKTask(
            id: TaskID.cardios,
            title: String(localized: "CARDIO_EXERCISES"),
            carePlanUUID: carePlanUUIDs[.wellness],
            schedule: cardioSchedule
        )
        cardios.impactsAdherence = true
        cardios.instructions = String(localized: "CARDIO_INSTRUCTIONS")
        cardios.card = .custom
        cardios.priority = 6
        cardios.carePlanUUID = carePlanUUIDs[.wellness]

        let stretchSchedule = OCKSchedule(composing: [
            OCKScheduleElement(start: beforeBreakfast, end: nil, interval: DateComponents(day: 1))
        ])
        var stretch = OCKTask(
            id: TaskID.stretch,
            title: String(localized: "STRETCH"),
            carePlanUUID: carePlanUUIDs[.wellness],
            schedule: stretchSchedule
        )
        stretch.impactsAdherence = true
        stretch.asset = "figure.flexibility"
        stretch.card = .simple
        stretch.priority = 5
        stretch.carePlanUUID = carePlanUUIDs[.wellness]

        // MARK: - 1. Log Focus (replaces inattention)
        // Behavioral Tracking — daily, all day
        let logFocusSchedule = OCKSchedule(composing: [
            OCKScheduleElement(
                start: beforeBreakfast, end: nil,
                interval: DateComponents(day: 1),
                text: String(localized: "ANYTIME_DURING_DAY"),
                targetValues: [], duration: .allDay
            )
        ])
        var logFocus = OCKTask(
            id: TaskID.logFocus,
            title: String(localized: "LOG_FOCUS"),
            carePlanUUID: carePlanUUIDs[.behavioralTracking],
            schedule: logFocusSchedule
        )
        logFocus.impactsAdherence = true
        logFocus.instructions = String(localized: "LOG_FOCUS_INSTRUCTIONS")
        logFocus.asset = "scope"
        logFocus.card = .button
        logFocus.priority = 10
        logFocus.carePlanUUID = carePlanUUIDs[.behavioralTracking]

        // MARK: - 2. Log Distraction
        // Behavioral Tracking — daily, all day
        let logDistractionSchedule = OCKSchedule(composing: [
            OCKScheduleElement(
                start: beforeBreakfast, end: nil,
                interval: DateComponents(day: 1),
                text: String(localized: "ANYTIME_DURING_DAY"),
                targetValues: [], duration: .allDay
            )
        ])
        var logDistraction = OCKTask(
            id: TaskID.logDistraction,
            title: String(localized: "LOG_DISTRACTION"),
            carePlanUUID: carePlanUUIDs[.behavioralTracking],
            schedule: logDistractionSchedule
        )
        logDistraction.impactsAdherence = false
        logDistraction.instructions = String(localized: "LOG_DISTRACTION_INSTRUCTIONS")
        logDistraction.asset = "exclamationmark.bubble"
        logDistraction.card = .button
        logDistraction.priority = 11
        logDistraction.carePlanUUID = carePlanUUIDs[.behavioralTracking]

        // MARK: - 3. Log Mood
        // Behavioral Tracking — daily at evening
        let moodTargetValue = OCKOutcomeValue(5.0) // target mood score of 5 out of 10
        let logMoodSchedule = OCKSchedule(composing: [
            OCKScheduleElement(
                start: evening, end: nil,
                interval: DateComponents(day: 1),
                text: String(localized: "ANYTIME_DURING_DAY"),
                targetValues: [moodTargetValue],
                duration: .allDay
            )
        ])
        var logMood = OCKTask(
            id: TaskID.logMood,
            title: String(localized: "LOG_MOOD"),
            carePlanUUID: carePlanUUIDs[.behavioralTracking],
            schedule: logMoodSchedule
        )
        logMood.impactsAdherence = true
        logMood.instructions = String(localized: "LOG_MOOD_INSTRUCTIONS")
        logMood.asset = "face.smiling"
        logMood.card = .grid
        logMood.priority = 12
        logMood.carePlanUUID = carePlanUUIDs[.behavioralTracking]

        // MARK: - 4. Log Sleep
        // Health — daily at morning (reviewing previous night)
        let logSleepSchedule = OCKSchedule(composing: [
            OCKScheduleElement(
                start: beforeBreakfast, end: nil,
                interval: DateComponents(day: 1),
                text: String(localized: "ANYTIME_DURING_DAY"),
                targetValues: [], duration: .allDay
            )
        ])
        var logSleep = OCKTask(
            id: TaskID.logSleep,
            title: String(localized: "LOG_SLEEP"),
            carePlanUUID: carePlanUUIDs[.health],
            schedule: logSleepSchedule
        )
        logSleep.impactsAdherence = true
        logSleep.instructions = String(localized: "LOG_SLEEP_INSTRUCTIONS")
        logSleep.asset = "bed.double.fill"
        logSleep.card = .button
        logSleep.priority = 13
        logSleep.carePlanUUID = carePlanUUIDs[.health]

        // MARK: - 5. Refocus Prompt
        // Adaptive Feedback — 3x daily (morning, lunch, afternoon)
        let refocusSchedule = OCKSchedule(composing: [
            OCKScheduleElement(start: beforeBreakfast, end: nil, interval: DateComponents(day: 1)),
            OCKScheduleElement(start: afterLunch, end: nil, interval: DateComponents(day: 1)),
            OCKScheduleElement(
                start: Calendar.current.date(byAdding: .hour, value: 16, to: aFewDaysAgo)!,
                end: nil, interval: DateComponents(day: 1)
            )
        ])
        var refocusPrompt = OCKTask(
            id: TaskID.refocusPrompt,
            title: String(localized: "REFOCUS_PROMPT"),
            carePlanUUID: carePlanUUIDs[.adaptiveFeedback],
            schedule: refocusSchedule
        )
        refocusPrompt.impactsAdherence = true
        refocusPrompt.instructions = String(localized: "REFOCUS_PROMPT_INSTRUCTIONS")
        refocusPrompt.asset = "arrow.uturn.forward.circle"
        refocusPrompt.card = .instruction
        refocusPrompt.priority = 14
        refocusPrompt.carePlanUUID = carePlanUUIDs[.adaptiveFeedback]

        // MARK: - 6. Breathing Exercise
        // Wellness — twice daily (morning, afternoon)
        let breathingSchedule = OCKSchedule(composing: [
            OCKScheduleElement(start: beforeBreakfast, end: nil, interval: DateComponents(day: 1)),
            OCKScheduleElement(
                start: Calendar.current.date(byAdding: .hour, value: 15, to: aFewDaysAgo)!,
                end: nil, interval: DateComponents(day: 1)
            )
        ])
        var breathingExercise = OCKTask(
            id: TaskID.breathingExercise,
            title: String(localized: "BREATHING_EXERCISE"),
            carePlanUUID: carePlanUUIDs[.wellness],
            schedule: breathingSchedule
        )
        breathingExercise.impactsAdherence = true
        breathingExercise.instructions = String(localized: "BREATHING_EXERCISE_INSTRUCTIONS")
        breathingExercise.asset = "wind"
        breathingExercise.card = .instruction
        breathingExercise.priority = 15
        breathingExercise.carePlanUUID = carePlanUUIDs[.wellness]

        // MARK: - 7. Take Break
        // Adaptive Feedback — twice daily (midday, afternoon)
        let takeBreakSchedule = OCKSchedule(composing: [
            OCKScheduleElement(start: afterLunch, end: nil, interval: DateComponents(day: 1)),
            OCKScheduleElement(
                start: Calendar.current.date(byAdding: .hour, value: 15, to: aFewDaysAgo)!,
                end: nil, interval: DateComponents(day: 1)
            )
        ])
        var takeBreak = OCKTask(
            id: TaskID.takeBreak,
            title: String(localized: "TAKE_BREAK"),
            carePlanUUID: carePlanUUIDs[.adaptiveFeedback],
            schedule: takeBreakSchedule
        )
        takeBreak.impactsAdherence = false
        takeBreak.instructions = String(localized: "TAKE_BREAK_INSTRUCTIONS")
        takeBreak.asset = "cup.and.saucer.fill"
        takeBreak.card = .simple
        takeBreak.priority = 16
        takeBreak.carePlanUUID = carePlanUUIDs[.adaptiveFeedback]

        // MARK: - 8. Weekly Reflection
        // Clinical Assessment — weekly
        let weeklyReflectionSchedule = OCKSchedule(composing: [
            OCKScheduleElement(
                start: evening, end: nil,
                interval: DateComponents(weekOfYear: 1)
            )
        ])
        var weeklyReflection = OCKTask(
            id: TaskID.weeklyReflection,
            title: String(localized: "WEEKLY_REFLECTION"),
            carePlanUUID: carePlanUUIDs[.clinicalAssessment],
            schedule: weeklyReflectionSchedule
        )
        weeklyReflection.impactsAdherence = false
        weeklyReflection.instructions = String(localized: "WEEKLY_REFLECTION_INSTRUCTIONS")
        weeklyReflection.asset = "text.book.closed.fill"
        weeklyReflection.card = .simple
        weeklyReflection.priority = 17
        weeklyReflection.carePlanUUID = carePlanUUIDs[.clinicalAssessment]

        // MARK: - Auto-detected exercise (inferred from HealthKit step patterns)
        // Wellness — all-day container for records written by ExerciseDetector.
        // Not user-facing as a "do this" task; outcomes represent detected sessions.
        let detectedExerciseSchedule = OCKSchedule(composing: [
            OCKScheduleElement(
                start: beforeBreakfast, end: nil,
                interval: DateComponents(day: 1),
                text: nil, targetValues: [], duration: .allDay
            )
        ])
        var detectedExercise = OCKTask(
            id: TaskID.detectedExercise,
            title: String(localized: "DETECTED_EXERCISE"),
            carePlanUUID: carePlanUUIDs[.wellness],
            schedule: detectedExerciseSchedule
        )
        detectedExercise.impactsAdherence = false
        detectedExercise.asset = "figure.walk.motion"
        detectedExercise.card = .simple
        detectedExercise.priority = 20
        detectedExercise.carePlanUUID = carePlanUUIDs[.wellness]

        // MARK: - Auto-detected mood spike (inferred from HR vs. step patterns)
        // All-day container for records written by HeartRateAnomalyDetector.
        let detectedMoodSchedule = OCKSchedule(composing: [
            OCKScheduleElement(
                start: beforeBreakfast, end: nil,
                interval: DateComponents(day: 1),
                text: nil, targetValues: [], duration: .allDay
            )
        ])
        var detectedMoodSpike = OCKTask(
            id: TaskID.detectedMoodSpike,
            title: String(localized: "DETECTED_MOOD_SPIKE"),
            carePlanUUID: carePlanUUIDs[.wellness],
            schedule: detectedMoodSchedule
        )
        detectedMoodSpike.impactsAdherence = false
        detectedMoodSpike.asset = "heart.text.square"
        detectedMoodSpike.card = .simple
        detectedMoodSpike.priority = 21
        detectedMoodSpike.carePlanUUID = carePlanUUIDs[.wellness]

        // MARK: - Add All Tasks
        #if os(iOS)
        let qualityOfLife = createQualityOfLifeSurveyTask(
            carePlanUUID: carePlanUUIDs[.clinicalAssessment]
        )
        #endif

        var tasksToAdd: [OCKTask] = [
            methylphenidate,
            cardios,
            stretch,
            logFocus,
            logDistraction,
            logMood,
            logSleep,
            refocusPrompt,
            breathingExercise,
            takeBreak,
            weeklyReflection,
            detectedExercise,
            detectedMoodSpike
        ]
        #if os(iOS)
        tasksToAdd.append(qualityOfLife)
        #endif
        _ = try await addTasksIfNotPresent(tasksToAdd)

        _ = try await addOnboardingTask(carePlanUUIDs[.health])
        _ = try await addUIKitSurveyTasks(carePlanUUIDs[.health])

        var contact1 = OCKContact(
            id: "jane",
            givenName: "Jane",
            familyName: "Daniels",
            carePlanUUID: nil
        )
        contact1.title = "Family Practice Doctor"
        contact1.role = "Dr. Daniels is a family practice doctor with 8 years of experience."
        contact1.emailAddresses = [OCKLabeledValue(label: CNLabelEmailiCloud, value: "janedaniels@uky.edu")]
        contact1.phoneNumbers = [OCKLabeledValue(label: CNLabelWork, value: "(800) 257-2000")]
        contact1.messagingNumbers = [OCKLabeledValue(label: CNLabelWork, value: "(800) 357-2040")]
        contact1.address = {
            let address = OCKPostalAddress(
				street: "1500 San Pablo St",
				city: "Los Angeles",
				state: "CA",
				postalCode: "90033",
				country: "US"
			)
            return address
        }()

        var contact2 = OCKContact(
            id: "matthew",
            givenName: "Matthew",
            familyName: "Reiff",
            carePlanUUID: nil
        )
        contact2.title = "OBGYN"
        contact2.role = "Dr. Reiff is an OBGYN with 13 years of experience."
        contact2.phoneNumbers = [OCKLabeledValue(label: CNLabelWork, value: "(800) 257-1000")]
        contact2.messagingNumbers = [OCKLabeledValue(label: CNLabelWork, value: "(800) 257-1234")]
        contact2.address = {
			let address = OCKPostalAddress(
				street: "1500 San Pablo St",
				city: "Los Angeles",
				state: "CA",
				postalCode: "90033",
				country: "US"
			)
            return address
        }()

        _ = try await addContactsIfNotPresent(
            [
                contact1,
                contact2
            ]
        )
    }
#if os(iOS)
    func createQualityOfLifeSurveyTask(carePlanUUID: UUID?) -> OCKTask {
            let qualityOfLifeTaskId = TaskID.qualityOfLife
            let thisMorning = Calendar.current.startOfDay(for: Date())
            let aFewDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: thisMorning)!
            let beforeBreakfast = Calendar.current.date(byAdding: .hour, value: 8, to: aFewDaysAgo)!
            let qualityOfLifeElement = OCKScheduleElement(
                start: beforeBreakfast,
                end: nil,
                interval: DateComponents(day: 1)
            )
            let qualityOfLifeSchedule = OCKSchedule(
                composing: [qualityOfLifeElement]
            )
            let textChoiceYesText = String(localized: "ANSWER_YES")
            let textChoiceNoText = String(localized: "ANSWER_NO")
            let yesValue = "Yes"
            let noValue = "No"
            let choices: [TextChoice] = [
                .init(
                    id: "\(qualityOfLifeTaskId)_0",
                    choiceText: textChoiceYesText,
                    value: yesValue
                ),
                .init(
                    id: "\(qualityOfLifeTaskId)_1",
                    choiceText: textChoiceNoText,
                    value: noValue
                )

            ]
            let questionOne = SurveyQuestion(
                id: "\(qualityOfLifeTaskId)-managing-time",
                type: .multipleChoice,
                required: true,
                title: String(localized: "QUALITY_OF_LIFE_TIME"),
                textChoices: choices,
                choiceSelectionLimit: .single
            )
            let questionTwo = SurveyQuestion(
                id: qualityOfLifeTaskId,
                type: .slider,
                required: false,
                title: String(localized: "QUALITY_OF_LIFE_STRESS"),
                detail: String(localized: "QUALITY_OF_LIFE_STRESS_DETAIL"),
                integerRange: 0...10,
                sliderStepValue: 1
            )
            let questions = [questionOne, questionTwo]
            let taskAsset = "brain.head.profile"
            let taskTitle = String(localized: "QUALITY_OF_LIFE")
            let stepOne = SurveyStep(
                id: "\(qualityOfLifeTaskId)-step-1",
                questions: questions,
                asset: taskAsset,
                title: taskTitle,
                subtitle: String(localized: "ANSWER_HONESTLY")
            )
            var qualityOfLife = OCKTask(
                id: "\(qualityOfLifeTaskId)-stress",
                title: String(localized: "QUALITY_OF_LIFE"),
                carePlanUUID: carePlanUUID,
                schedule: qualityOfLifeSchedule
            )
            qualityOfLife.impactsAdherence = true
            qualityOfLife.asset = "brain.head.profile"
            qualityOfLife.card = .survey
            qualityOfLife.surveySteps = [stepOne]
            qualityOfLife.priority = 2
            qualityOfLife.carePlanUUID = carePlanUUID

            return qualityOfLife
        }
#endif
    func addOnboardingTask(_ carePlanUUID: UUID? = nil) async throws -> [OCKTask] {

        let onboardSchedule = OCKSchedule.dailyAtTime(
            hour: 0, minutes: 0,
            start: Date(), end: nil,
            text: "Task Due!",
            duration: .allDay
        )

        var onboardTask = OCKTask(
            id: Onboard.identifier(),
            title: "Onboard",
            carePlanUUID: carePlanUUID,
            schedule: onboardSchedule
        )
        onboardTask.instructions = "You'll need to agree to some terms and conditions before we get started!"
        onboardTask.impactsAdherence = false
        onboardTask.card = .uiKitSurvey
        onboardTask.uiKitSurvey = .onboard

        return try await addTasksIfNotPresent([onboardTask])
    }

    func addUIKitSurveyTasks(_ carePlanUUID: UUID? = nil) async throws -> [OCKTask] {
        let thisMorning = Calendar.current.startOfDay(for: Date())

        let nextWeek = Calendar.current.date(
            byAdding: .weekOfYear,
            value: 1,
            to: Date()
        )!

        let nextMonth = Calendar.current.date(
            byAdding: .month,
            value: 1,
            to: thisMorning
        )

        let dailyElement = OCKScheduleElement(
            start: thisMorning,
            end: nextWeek,
            interval: DateComponents(day: 1),
            text: nil,
            targetValues: [],
            duration: .allDay
        )

        let weeklyElement = OCKScheduleElement(
            start: nextWeek,
            end: nextMonth,
            interval: DateComponents(weekOfYear: 1),
            text: nil,
            targetValues: [],
            duration: .allDay
        )

        let rangeOfMotionCheckSchedule = OCKSchedule(
            composing: [dailyElement, weeklyElement]
        )

        var rangeOfMotionTask = OCKTask(
            id: RangeOfMotion.identifier(),
            title: "Range Of Motion",
            carePlanUUID: carePlanUUID,
            schedule: rangeOfMotionCheckSchedule
        )
        rangeOfMotionTask.priority = 4
        rangeOfMotionTask.asset = "figure.walk.motion"
        rangeOfMotionTask.card = .uiKitSurvey
        rangeOfMotionTask.uiKitSurvey = .rangeOfMotion

        return try await addTasksIfNotPresent([rangeOfMotionTask])
    }
}
