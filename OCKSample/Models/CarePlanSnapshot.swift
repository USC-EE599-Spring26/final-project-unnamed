//
//  CarePlanSnapshot.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/27.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//
//  Lightweight Codable snapshot of an OCKCarePlan + its OCKTasks.
//  Stored as a JSON string in CarePlanAssignment.payload so the patient's
//  app can reconstruct the care plan without needing read access to the
//  clinician's ParseCareKit data partition.
//

import CareKitStore
import Foundation

// MARK: - Top-level snapshot

struct CarePlanSnapshot: Codable {
    let carePlanId: String
    let carePlanTitle: String?      // OCKCarePlan.title is optional in CareKit
    let tasks: [TaskSnapshot]
}

// MARK: - Task snapshot

struct TaskSnapshot: Codable {
    let id: String
    let title: String?          // OCKTask.title is optional in CareKit
    let instructions: String?
    let impactsAdherence: Bool
    let scheduleElements: [ScheduleElementSnapshot]
}

// MARK: - Schedule element snapshot

struct ScheduleElementSnapshot: Codable {
    let start: Date
    let end: Date?
    let intervalComponents: DateComponents
    let text: String?
    let isAllDay: Bool
    let durationSeconds: Double     // ignored when isAllDay == true
}

// MARK: - CarePlanSnapshot helpers

extension CarePlanSnapshot {

    /// Build a snapshot from the clinician's care plan and its tasks.
    init(plan: OCKCarePlan, tasks: [OCKTask]) {
        carePlanId    = plan.id
        carePlanTitle = plan.title          // String? — preserved as-is
        self.tasks    = tasks.map { TaskSnapshot(task: $0) }
    }

    /// Serialise to a JSON string for storage in Parse.
    func toJSONString() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let str = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "CarePlanSnapshot", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "UTF-8 encoding failed"]
            )
        }
        return str
    }

    /// Deserialise from the JSON string stored in Parse.
    static func from(jsonString: String) throws -> CarePlanSnapshot {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(
                domain: "CarePlanSnapshot", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "UTF-8 decoding failed"]
            )
        }
        return try JSONDecoder().decode(CarePlanSnapshot.self, from: data)
    }
}

// MARK: - TaskSnapshot helpers

extension TaskSnapshot {

    init(task: OCKTask) {
        id               = task.id
        title            = task.title
        instructions     = task.instructions
        impactsAdherence = task.impactsAdherence
        scheduleElements = task.schedule.elements.map { ScheduleElementSnapshot(element: $0) }
    }

    /// Reconstruct an OCKTask that belongs to the patient's care plan.
    func toOCKTask(carePlanUUID: UUID) -> OCKTask {
        let elements = scheduleElements.map { $0.toOCKScheduleElement() }
        let schedule = OCKSchedule(composing: elements)
        var task = OCKTask(
            id: id,
            title: title,
            carePlanUUID: carePlanUUID,
            schedule: schedule
        )
        task.instructions    = instructions
        task.impactsAdherence = impactsAdherence
        return task
    }
}

// MARK: - ScheduleElementSnapshot helpers

extension ScheduleElementSnapshot {

    init(element: OCKScheduleElement) {
        start              = element.start
        end                = element.end
        intervalComponents = element.interval
        text               = element.text
        switch element.duration {
        case .allDay:
            isAllDay        = true
            durationSeconds = 0
        case .seconds(let secs):
            isAllDay        = false
            durationSeconds = secs
        @unknown default:
            isAllDay        = false
            durationSeconds = 3_600
        }
    }

    func toOCKScheduleElement() -> OCKScheduleElement {
        let duration: OCKScheduleElement.Duration = isAllDay
            ? .allDay
            : .seconds(durationSeconds)
        return OCKScheduleElement(
            start: start,
            end: end,
            interval: intervalComponents,
            text: text,
            targetValues: [],
            duration: duration
        )
    }
}
