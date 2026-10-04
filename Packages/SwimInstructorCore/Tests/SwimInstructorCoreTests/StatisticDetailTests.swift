import XCTest
@testable import SwimInstructorCore

/// Was hinter einem Balken oder Punkt steckt, die Werte einer einzelnen Einheit und der Pulsverlauf im Detail. Feste
/// Daten aus `StatisticData`: "Heute" ist Mittwoch, der 30.09.2026.
final class StatisticDetailTests: XCTestCase {
    private let calculator = StatisticData.calculator

    private func point(_ result: StatisticResult, daysAgo: Int) throws -> StatisticPoint {
        let start = TestFixtures.date(daysAgo: daysAgo, hour: 0)
        return try XCTUnwrap(result.series.first { $0.start == start })
    }

    // MARK: - Abschnitte

    func testEveryPointKnowsWhereItEnds() throws {
        let days = StatisticData.result("run", .distance, .sevenDays)
        let today = try point(days, daysAgo: 0)
        XCTAssertEqual(today.end, TestFixtures.date(daysAgo: -1, hour: 0))

        let weeks = StatisticData.result("run", .distance, .fourWeeks)
        let last = try XCTUnwrap(weeks.series.last)
        XCTAssertEqual(last.start, TestFixtures.date(daysAgo: 6, hour: 0))
        XCTAssertEqual(last.end, TestFixtures.date(daysAgo: -1, hour: 0))
    }

    // MARK: - Was dahinter steckt

    func testADayShowsTheWorkoutsOfTheTileSportOnly() throws {
        let swim = StatisticData.result("swim", .distance, .sevenDays)
        let breakdown = calculator.breakdown(of: swim, at: try point(swim, daysAgo: 1), input: StatisticData.input)

        XCTAssertEqual(breakdown.workouts.map(\.sport), ["swim"])
        XCTAssertEqual(breakdown.workouts.first?.distanceMeters, 2000)
        XCTAssertTrue(breakdown.days.isEmpty)
        XCTAssertTrue(breakdown.planDays.isEmpty)
    }

    func testAllSportsShowEveryWorkoutOfTheDay() throws {
        let all = StatisticData.result(nil, .duration, .sevenDays)
        let breakdown = calculator.breakdown(of: all, at: try point(all, daysAgo: 1), input: StatisticData.input)

        XCTAssertEqual(Set(breakdown.workouts.map(\.sport)), ["swim", "rowing"])
    }

    func testAWeekShowsItsWorkoutsNewestFirst() throws {
        let weeks = StatisticData.result("run", .distance, .fourWeeks)
        let breakdown = calculator.breakdown(of: weeks, at: try XCTUnwrap(weeks.series.last), input: StatisticData.input)

        XCTAssertEqual(breakdown.workouts.map(\.distanceMeters), [10000, 6000])
    }

    func testVitalsShowTheDayValueInTheUnitOfTheMetric() throws {
        let resting = StatisticData.result(nil, .restingHeartRate, .sevenDays)
        XCTAssertEqual(
            calculator.breakdown(of: resting, at: try point(resting, daysAgo: 1), input: StatisticData.input).days.map(\.value),
            [52]
        )

        let sleep = StatisticData.result(nil, .sleep, .sevenDays)
        XCTAssertEqual(
            calculator.breakdown(of: sleep, at: try point(sleep, daysAgo: 1), input: StatisticData.input).days.map(\.value),
            [7 * 3600]
        )
        // Ohne Messung an dem Tag: nichts, auch keine Einheiten.
        let noSleep = calculator.breakdown(of: sleep, at: try point(sleep, daysAgo: 0), input: StatisticData.input)
        XCTAssertTrue(noSleep.isEmpty)
    }

    func testPlanAdherenceShowsTheDayWithItsPlan() throws {
        let adherence = StatisticData.result(nil, .planAdherence, .sevenDays)
        let breakdown = calculator.breakdown(of: adherence, at: try point(adherence, daysAgo: 1), input: StatisticData.input)

        XCTAssertEqual(breakdown.planDays.map(\.date), ["2026-09-29"])
        XCTAssertEqual(breakdown.planDays.first?.outcome, .followed)
        XCTAssertTrue(breakdown.workouts.isEmpty)
    }

    // MARK: - Werte einer Einheit

    func testOneWorkoutGetsItsOwnPace() throws {
        let run = try XCTUnwrap(StatisticData.workouts.first { $0.sport == "run" && $0.distanceMeters == 10000 })
        XCTAssertEqual(try XCTUnwrap(calculator.value(.pacePerKilometer, of: run, input: StatisticData.input)), 300, accuracy: 0.001)
        // Tageswerte gehören zu keiner Einheit.
        XCTAssertNil(calculator.value(.restingHeartRate, of: run, input: StatisticData.input))
    }

    func testWorkoutValuesFollowTheCatalogOfItsSport() throws {
        let run = try XCTUnwrap(StatisticData.workouts.first { $0.sport == "run" && $0.distanceMeters == 10000 })
        let values = calculator.values(of: run, input: StatisticData.input)
        let byMetric = Dictionary(uniqueKeysWithValues: values.map { ($0.definition.metric, $0.value) })

        XCTAssertEqual(values.first?.definition.metric, .distance)
        XCTAssertEqual(byMetric[.distance], 10000)
        XCTAssertEqual(byMetric[.duration], 3000)
        XCTAssertEqual(byMetric[.averageHeartRate], 150)
        XCTAssertEqual(byMetric[.averagePower], 250)
        XCTAssertEqual(byMetric[.elevationGain], 80)
        XCTAssertNotNil(byMetric[.trainingLoad])
        // Für eine einzelne Einheit sinnlos.
        XCTAssertNil(byMetric[.sessions])
        XCTAssertNil(byMetric[.longestDistance])
    }

    func testWorkoutValuesLeaveOutWhatTheWorkoutDidNotMeasure() throws {
        let rowing = try XCTUnwrap(StatisticData.workouts.first { $0.sport == "rowing" })
        let metrics = calculator.values(of: rowing, input: StatisticData.input).map(\.definition.metric)

        XCTAssertFalse(metrics.contains(.distance))
        XCTAssertFalse(metrics.contains(.speed))
        XCTAssertTrue(metrics.contains(.duration))
        XCTAssertTrue(metrics.contains(.averagePower))
    }

    func testAnUnknownSportStillShowsTimePulseAndLoad() {
        let kayak = StatisticData.workout("kayak", daysAgo: 0, minutes: 30, meters: 5000, heartRate: 120)
        let metrics = calculator.values(of: kayak, input: StatisticData.input).map(\.definition.metric)

        XCTAssertEqual(metrics, [.duration, .averageHeartRate, .trainingLoad])
    }

    // MARK: - Texte

    func testPointTitlesAndAxisLabels() throws {
        let calendar = TestFixtures.utc
        let days = StatisticData.result("run", .distance, .sevenDays)
        let today = try point(days, daysAgo: 0)
        XCTAssertEqual(StatisticFormatting.axisLabel(today, calendar: calendar), "Mi")
        XCTAssertEqual(StatisticFormatting.pointTitle(today, calendar: calendar), "Mittwoch, 30.9.")

        let weeks = StatisticData.result("run", .distance, .fourWeeks)
        let first = try XCTUnwrap(weeks.series.first)
        XCTAssertEqual(StatisticFormatting.axisLabel(first, calendar: calendar), "3.9.")
        XCTAssertEqual(StatisticFormatting.pointTitle(first, calendar: calendar), "3.9. – 9.9.")
    }

    func testWorkoutTexts() throws {
        let run = try XCTUnwrap(StatisticData.workouts.first { $0.sport == "run" && $0.distanceMeters == 10000 })
        XCTAssertEqual(StatisticFormatting.workoutTime(run, calendar: TestFixtures.utc), "Mittwoch, 30.9.2026, 08:00 – 08:50")
        XCTAssertEqual(StatisticFormatting.workoutValueName(.distanceKilometers), "Strecke")
        XCTAssertEqual(StatisticFormatting.workoutValueName(.duration), "Dauer")
        XCTAssertEqual(StatisticFormatting.workoutValueName(.pacePerKilometer), "Pace pro km")
    }

    // MARK: - Puls

    func testHeartRateCurveAveragesIntoPointsAndKeepsTheRealPeak() {
        let start = TestFixtures.now
        let end = start.addingTimeInterval(600)
        let samples = [
            HeartRateSample(date: start.addingTimeInterval(10), beatsPerMinute: 100),
            HeartRateSample(date: start.addingTimeInterval(50), beatsPerMinute: 120),
            HeartRateSample(date: start.addingTimeInterval(400), beatsPerMinute: 170),
            // Vor dem Start und ungültig: zählen nicht.
            HeartRateSample(date: start.addingTimeInterval(-60), beatsPerMinute: 190),
            HeartRateSample(date: start.addingTimeInterval(500), beatsPerMinute: 0)
        ]
        let curve = HeartRateCurve(samples: samples, start: start, end: end, maxPoints: 10)

        // Abschnitte zu je einer Minute; die ohne Messung fallen weg.
        XCTAssertEqual(curve.points, [
            HeartRateCurve.Point(minute: 0.5, beatsPerMinute: 110),
            HeartRateCurve.Point(minute: 6.5, beatsPerMinute: 170)
        ])
        XCTAssertEqual(curve.maximum, 170)
        XCTAssertEqual(curve.minimum, 100)
    }

    func testHeartRateCurveWithoutSamplesIsEmpty() {
        let curve = HeartRateCurve(samples: [], start: TestFixtures.now, end: TestFixtures.now.addingTimeInterval(600))
        XCTAssertTrue(curve.points.isEmpty)
        XCTAssertNil(curve.maximum)
    }
}
