import XCTest
@testable import SwimInstructorCore

final class DailyVitalsAggregatorTests: XCTestCase {
    private let aggregator = DailyVitalsAggregator(calendar: TestFixtures.utc)

    private func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        TestFixtures.date(daysAgo: daysAgo, hour: hour).addingTimeInterval(TimeInterval(minute * 60))
    }

    func testNightCountsForWakeUpDay() {
        // 23:00 vorgestern bis 07:00 gestern: 8 Stunden, gehören zu gestern.
        let hours = aggregator.sleepHoursPerDay([
            SleepInterval(start: at(daysAgo: 2, hour: 23), end: at(daysAgo: 1, hour: 7))
        ])

        XCTAssertEqual(hours, [TestFixtures.utc.startOfDay(for: at(daysAgo: 1, hour: 0)): 8])
    }

    func testOverlappingSourcesAreNotCountedTwice() {
        // Watch meldet 23:00 bis 06:00, iPhone 23:30 bis 06:30: zusammen 7,5 Stunden, nicht 14.
        let hours = aggregator.sleepHoursPerDay([
            SleepInterval(start: at(daysAgo: 1, hour: 23), end: at(daysAgo: 0, hour: 6)),
            SleepInterval(start: at(daysAgo: 1, hour: 23, minute: 30), end: at(daysAgo: 0, hour: 6, minute: 30))
        ])

        XCTAssertEqual(hours[TestFixtures.utc.startOfDay(for: TestFixtures.now)], 7.5)
    }

    func testSeparatePhasesAndWakePhaseGapAddUp() {
        // Kernschlaf 23 bis 2 Uhr, 30 min wach (nicht übergeben), Tiefschlaf 2:30 bis 6 Uhr.
        let hours = aggregator.sleepHoursPerDay([
            SleepInterval(start: at(daysAgo: 1, hour: 23), end: at(daysAgo: 0, hour: 2)),
            SleepInterval(start: at(daysAgo: 0, hour: 2, minute: 30), end: at(daysAgo: 0, hour: 6))
        ])

        XCTAssertEqual(hours[TestFixtures.utc.startOfDay(for: TestFixtures.now)], 6.5)
    }

    func testIgnoresEmptyOrInvertedIntervals() {
        let hours = aggregator.sleepHoursPerDay([
            SleepInterval(start: at(daysAgo: 0, hour: 5), end: at(daysAgo: 0, hour: 5)),
            SleepInterval(start: at(daysAgo: 0, hour: 6), end: at(daysAgo: 0, hour: 5))
        ])

        XCTAssertTrue(hours.isEmpty)
    }

    func testAssembleMergesByDayAndSorts() {
        let today = TestFixtures.utc.startOfDay(for: TestFixtures.now)
        let yesterday = TestFixtures.utc.startOfDay(for: at(daysAgo: 1, hour: 0))

        let vitals = aggregator.assemble(
            restingHeartRate: [at(daysAgo: 0, hour: 8): 52, at(daysAgo: 1, hour: 8): 54],
            hrvSDNN: [at(daysAgo: 0, hour: 3): 60],
            sleepHours: [yesterday: 7]
        )

        XCTAssertEqual(vitals, [
            DailyVitals(date: yesterday, restingHeartRate: 54, hrvSDNN: nil, sleepHours: 7),
            DailyVitals(date: today, restingHeartRate: 52, hrvSDNN: 60, sleepHours: nil)
        ])
    }

    func testAssembleAveragesSeveralValuesOfTheSameDay() {
        let vitals = aggregator.assemble(
            restingHeartRate: [at(daysAgo: 0, hour: 1): 50, at(daysAgo: 0, hour: 9): 54],
            hrvSDNN: [:],
            sleepHours: [:]
        )

        XCTAssertEqual(vitals.count, 1)
        XCTAssertEqual(vitals.first?.restingHeartRate, 52)
    }
}
