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
import HealthKit
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
			let startOfDay = calendar.startOfDay(for: now)
			let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
			period = .day
			chartInterval = DateInterval(start: startOfDay, end: endOfDay)

		case 1:
			let startDate = calendar.date(
				byAdding: .day,
				value: -6,
				to: calendar.startOfDay(for: now)
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
				byAdding: .day,
				value: -6,
				to: calendar.startOfDay(for: now)
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
	@State private var healthKitData: [ChartPoint]?

	static func makeQuery() -> OCKEventQuery {
		OCKEventQuery(dateInterval: .init())
	}

	private var isHealthKitBacked: Bool {
		taskIDs == [TaskID.steps]
	}

	private var displayData: [ChartPoint] {
		if isHealthKitBacked, let healthKitData {
			return healthKitData
		}
		return chartData
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(title)
				.font(.headline)
			Text(subtitle)
				.font(.caption)
				.foregroundStyle(.secondary)
			Chart(displayData) { point in
				BarMark(
					x: .value("Date", point.date, unit: binComponent),
					y: .value("Value", point.value)
				)
				.foregroundStyle(by: .value("Series", point.series))
			}
			.chartXScale(domain: dateInterval.start ... paddedEnd)
			.chartYScale(domain: .automatic(includesZero: true))
			.chartYAxis {
				AxisMarks(position: .leading) { _ in
					AxisGridLine()
					AxisTick()
					AxisValueLabel()
				}
			}
			.chartXAxis {
				AxisMarks(values: .stride(by: binComponent)) { _ in
					AxisGridLine()
					AxisTick()
					AxisValueLabel(format: xAxisFormat, centered: true)
				}
			}
			.frame(height: 220)
		}
		.padding()
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
		.onAppear {
			updateQuery()
			refreshHealthKitIfNeeded()
		}
		.onChange(of: dateInterval) {
			updateQuery()
			refreshHealthKitIfNeeded()
		}
		.onChange(of: taskIDs) {
			updateQuery()
			refreshHealthKitIfNeeded()
		}
		.onChange(of: binComponent) {
			refreshHealthKitIfNeeded()
		}
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

	private func refreshHealthKitIfNeeded() {
		guard isHealthKitBacked else {
			healthKitData = nil
			return
		}
		let interval = dateInterval
		let bin = binComponent
		Task { @MainActor in
			let points = await Self.queryHealthKitSteps(in: interval, bin: bin)
			self.healthKitData = points
		}
	}

	private static func queryHealthKitSteps(
		in interval: DateInterval,
		bin: Calendar.Component
	) async -> [ChartPoint] {
		guard HKHealthStore.isHealthDataAvailable(),
			  let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
		else { return [] }
		let store = HKHealthStore()
		do {
			try await store.requestAuthorization(toShare: [], read: [stepType])
		} catch {
			return []
		}
		let intervalComponents: DateComponents
		switch bin {
		case .hour: intervalComponents = DateComponents(hour: 1)
		case .month: intervalComponents = DateComponents(month: 1)
		default: intervalComponents = DateComponents(day: 1)
		}
		let predicate = HKQuery.predicateForSamples(
			withStart: interval.start,
			end: interval.end,
			options: .strictStartDate
		)
		return await withCheckedContinuation { continuation in
			let query = HKStatisticsCollectionQuery(
				quantityType: stepType,
				quantitySamplePredicate: predicate,
				options: .cumulativeSum,
				anchorDate: interval.start,
				intervalComponents: intervalComponents
			)
			query.initialResultsHandler = { _, results, _ in
				var points: [ChartPoint] = []
				results?.enumerateStatistics(
					from: interval.start,
					to: interval.end
				) { statistics, _ in
					let count = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
					if count > 0 {
						points.append(
							ChartPoint(
								date: statistics.startDate,
								value: count,
								series: TaskID.steps
							)
						)
					}
				}
				continuation.resume(returning: points)
			}
			store.execute(query)
		}
	}

	private var chartData: [ChartPoint] {
		let calendar = Calendar.current
		var points: [ChartPoint] = []
		for taskID in taskIDs {
			let filtered = events.filter { $0.result.task.id == taskID }
			// Bin per outcome value (using its createdDate) so all-day tasks
			// don't collapse all logs into the schedule's start hour.
			var bucketed: [Date: Double] = [:]
			for entry in filtered {
				let event = entry.result
				guard let values = event.outcome?.values, !values.isEmpty else { continue }
				for value in values {
					let referenceDate = value.createdDate
					let binDate: Date
					if let interval = calendar.dateInterval(of: binComponent, for: referenceDate) {
						binDate = interval.start
					} else {
						binDate = referenceDate
					}
					bucketed[binDate, default: 0] += Self.extractValue(value)
				}
			}
			for (date, total) in bucketed {
				points.append(ChartPoint(date: date, value: total, series: taskID))
			}
		}
		return points.sorted { $0.date < $1.date }
	}

	private var paddedEnd: Date {
		let calendar = Calendar.current
		let anchor = calendar.dateInterval(of: binComponent, for: dateInterval.end)?.start
			?? dateInterval.end
		return calendar.date(byAdding: binComponent, value: 1, to: anchor) ?? dateInterval.end
	}

	private var xAxisFormat: Date.FormatStyle {
		switch binComponent {
		case .hour: return .dateTime.hour()
		case .month: return .dateTime.month(.abbreviated)
		default: return .dateTime.month(.abbreviated).day()
		}
	}

	private static func extractValue(_ value: OCKOutcomeValue) -> Double {
		if let double = value.doubleValue { return double }
		if let integer = value.integerValue { return Double(integer) }
		if let boolean = value.booleanValue { return boolean ? 1 : 0 }
		return 1
	}
}
