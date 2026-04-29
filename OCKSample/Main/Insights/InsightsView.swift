//
//  InsightsView.swift
//  OCKSample
//
//  Created by Corey Baker on 4/17/25.
//  Copyright © 2025 Network Reconnaissance Lab. All rights reserved.
//

import CareKit
import CareKitEssentials
import CareKitStore
import CareKitUI
import SwiftUI
import Charts

struct InsightsView: View {

	@CareStoreFetchRequest(query: query()) private var events
	@State var intervalSelected = 0 // Default to week since chart isn't working for others.
	@State var chartInterval = DateInterval()
	@State var period: PeriodComponent = .day
	@State var configurations: [CKEDataSeriesConfiguration] = []
	@State var sortedTaskIDs: [String: Int] = [:]

    var body: some View {
		NavigationStack {
			dateIntervalSegmentView
				.padding()
			ScrollView {
				VStack(spacing: 16) {
					ForEach(orderedEvents) { event in
						let eventResult = event.result
						if eventResult.task.id != TaskID.methylphenidate
							&& eventResult.task.id != TaskID.inattention {
							chartCard(
								taskID: eventResult.task.id,
								title: eventResult.title
							)
						} else if eventResult.task.id == TaskID.methylphenidate {
							chartCard(
								taskIDs: [TaskID.inattention, TaskID.methylphenidate],
								title: String(localized: "INATTENTION_METHYLPHENIDATE_INTAKE")
							)
						}
					}
				}
				.padding()
			}
			.onAppear {
				let taskIDs = TaskID.orderedWatchOS + TaskID.orderedObjective
				sortedTaskIDs = computeTaskIDOrder(taskIDs: taskIDs)
				events.query.taskIDs = taskIDs
				events.query.dateInterval = eventQueryInterval
				setupChartPropertiesForSegmentSelection(intervalSelected)
			}
#if os(iOS)
			.onChange(of: intervalSelected) { _, intervalSegmentValue in
				setupChartPropertiesForSegmentSelection(intervalSegmentValue)
			}
#else
			.onChange(of: intervalSelected, initial: true) { _, newSegmentValue in
				setupChartPropertiesForSegmentSelection(newSegmentValue)
			}
#endif
		}
    }

	private var orderedEvents: [CareStoreFetchedResult<OCKAnyEvent>] {
		events.latest.sorted(by: { left, right in
			let leftTaskID = left.result.task.id
			let rightTaskID = right.result.task.id

			return sortedTaskIDs[leftTaskID] ?? 0 < sortedTaskIDs[rightTaskID] ?? 0
		})
	}

	private var dateIntervalSegmentView: some View {
		Picker(
			"CHOOSE_DATE_INTERVAL",
			selection: $intervalSelected.animation()
		) {
			Text("TODAY")
				.tag(0)
			Text("WEEK")
				.tag(1)
			Text("MONTH")
				.tag(2)
			Text("YEAR")
				.tag(3)
		}
		#if !os(watchOS)
		.pickerStyle(.segmented)
		#else
		.pickerStyle(.automatic)
		#endif
	}

	private var subtitle: String {
		switch intervalSelected {
		case 0:
			return String(localized: "TODAY")
		case 1:
			return String(localized: "WEEK")
		case 2:
			return String(localized: "MONTH")
		case 3:
			return String(localized: "YEAR")
		default:
			return String(localized: "WEEK")
		}
	}

	// Currently only look for events for the last.
	// We don't need to vary this because it's only
	// used to find taskID's. The chartInterval will
	// find all of the needed data for the chart.
	private var eventQueryInterval: DateInterval {
		let interval = Calendar.current.dateInterval(
			of: .weekOfYear,
			for: Date()
		)!
		return interval
	}

	private var binComponent: Calendar.Component {
		switch intervalSelected {
		case 0: return .hour
		case 3: return .month
		default: return .day
		}
	}

	@ViewBuilder
	private func chartCard(taskID: String, title: String) -> some View {
		ChartCardView(
			title: title,
			subtitle: subtitle,
			taskIDs: [taskID],
			dateInterval: chartInterval,
			binComponent: binComponent
		)
	}

	@ViewBuilder
	private func chartCard(taskIDs: [String], title: String) -> some View {
		ChartCardView(
			title: title,
			subtitle: subtitle,
			taskIDs: taskIDs,
			dateInterval: chartInterval,
			binComponent: binComponent
		)
	}

	private func determineDataStrategy(for taskID: String) -> CKEDataSeriesConfiguration.DataStrategy {
		switch taskID {
		case /*TaskID.ovulationTestResult,*/ TaskID.steps:
			return .max
		default:
			return .mean
		}
	}

	private func setupChartPropertiesForSegmentSelection(_ segmentValue: Int) {
		let now = Date()
		let calendar = Calendar.current
		// This changes the interval of what will be
		// shown in the graph.
		switch segmentValue {
		case 0:
			let startOfDay = Calendar.current.startOfDay(
				for: now
			)
			let interval = DateInterval(
				start: startOfDay,
				end: now
			)

			period = .day
			chartInterval = interval

		case 1:
			let startDate = calendar.date(
				byAdding: .weekday,
				value: -7,
				to: now
			)!
			period = .week
			chartInterval = DateInterval(start: startDate, end: now)

		case 2:
			let startDate = calendar.date(
				byAdding: .month,
				value: -1,
				to: now
			)!
			period = .month
			chartInterval = DateInterval(start: startDate, end: now)

		case 3:
			let startDate = calendar.date(
				byAdding: .year,
				value: -1,
				to: now
			)!
			period = .month
			chartInterval = DateInterval(start: startDate, end: now)

		default:
			let startDate = calendar.date(
				byAdding: .weekday,
				value: -7,
				to: now
			)!
			period = .week
			chartInterval = DateInterval(start: startDate, end: now)

		}
	}

	private func computeTaskIDOrder(taskIDs: [String]) -> [String: Int] {
		// Tie index values to TaskIDs.
		let sortedTaskIDs = taskIDs.enumerated().reduce(into: [String: Int]()) { taskDictionary, task in
			taskDictionary[task.element] = task.offset
		}

		return sortedTaskIDs
	}

	static func query() -> OCKEventQuery {
		let query = OCKEventQuery(dateInterval: .init())
		return query
	}
}

#Preview {
    InsightsView()
		.environment(\.careStore, Utility.createPreviewStore())
		.careKitStyle(Styler())
}

private struct ChartPoint: Identifiable {
	let id = UUID()
	let date: Date
	let value: Double
	let series: String
}

private struct ChartCardView: View {
	let title: String
	let subtitle: String
	let taskIDs: [String]
	let dateInterval: DateInterval
	let binComponent: Calendar.Component

	@CareStoreFetchRequest(query: Self.makeQuery()) private var events

	static func makeQuery() -> OCKEventQuery {
		OCKEventQuery(dateInterval: .init())
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title)
				.font(.headline)
			Text(subtitle)
				.font(.caption)
				.foregroundStyle(.secondary)
			Chart(chartData) { point in
				BarMark(
					x: .value("Date", point.date, unit: binComponent),
					y: .value("Value", point.value)
				)
				.foregroundStyle(by: .value("Series", point.series))
			}
			.chartYAxis {
				AxisMarks(position: .leading)
			}
			.chartXAxis {
				AxisMarks()
			}
			.frame(height: 220)
		}
		.padding()
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
		.onAppear { updateQuery() }
		.onChange(of: dateInterval) { updateQuery() }
		.onChange(of: taskIDs) { updateQuery() }
	}

	private func updateQuery() {
		let desired = Set(taskIDs)
		if Set(events.query.taskIDs) != desired {
			events.query.taskIDs = Array(desired)
		}
		if events.query.dateInterval != dateInterval {
			events.query.dateInterval = dateInterval
		}
	}

	private var chartData: [ChartPoint] {
		let calendar = Calendar.current
		var points: [ChartPoint] = []
		for taskID in taskIDs {
			let filtered = events.filter { $0.result.task.id == taskID }
			let grouped = Dictionary(grouping: filtered) { result -> Date in
				calendar.dateInterval(of: binComponent, for: result.result.scheduleEvent.start)?.start
					?? result.result.scheduleEvent.start
			}
			for (date, evts) in grouped {
				let total = evts.reduce(0.0) { sum, evt in
					sum + (evt.result.outcome?.values.map(Self.extractValue).reduce(0, +) ?? 0)
				}
				points.append(ChartPoint(date: date, value: total, series: taskID))
			}
		}
		return points.sorted { $0.date < $1.date }
	}

	private static func extractValue(_ value: OCKOutcomeValue) -> Double {
		if let double = value.doubleValue { return double }
		if let integer = value.integerValue { return Double(integer) }
		if let boolean = value.booleanValue { return boolean ? 1 : 0 }
		return 1
	}
}
