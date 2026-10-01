import XCTest
@testable import SwimInstructorCore

final class TrainingStatisticsTests: XCTestCase {
    /// Montag als Wochenbeginn, wie auf einem deutschen Gerät. 30.09.2026 ist ein Mittwoch.
    private let calendar: Calendar = {
        var calendar = TestFixtures.utc
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    private var statistics: TrainingStatistics { TrainingStatistics(calendar: calendar) }

    func testWeeklyVolumesGroupByCalendarWeekOldestFirst() {
        let workouts = [
            TestFixtures.workout(daysAgo: 1, meters: 1000, seconds: 1800),   // Di 29.09., laufende Woche
            TestFixtures.workout(daysAgo: 2, meters: 500, seconds: 900),     // Mo 28.09., laufende Woche
            TestFixtures.workout(daysAgo: 3, meters: 2000, seconds: 3600)    // So 27.09., Vorwoche
        ]

        let weeks = statistics.weeklyVolumes(workouts: workouts, weeks: 8, now: TestFixtures.now)

        XCTAssertEqual(weeks.count, 8)
        XCTAssertEqual(weeks.map(\.isCurrentWeek), [false, false, false, false, false, false, false, true])
        let current = weeks[7]
        XCTAssertEqual(current.weekStart, TestFixtures.date(daysAgo: 2, hour: 0))
        XCTAssertEqual(current.meters, 1500)
        XCTAssertEqual(current.sessions, 2)
        XCTAssertEqual(current.averagePaceSecondsPer100m ?? 0, 180, accuracy: 0.001)
        let previous = weeks[6]
        XCTAssertEqual(previous.weekStart, TestFixtures.date(daysAgo: 9, hour: 0))
        XCTAssertEqual(previous.meters, 2000)
        XCTAssertEqual(previous.sessions, 1)
        XCTAssertEqual(previous.averagePaceSecondsPer100m ?? 0, 180, accuracy: 0.001)
    }

    func testWeeksWithoutSessionsAreZeroNotMissing() {
        let weeks = statistics.weeklyVolumes(workouts: [], weeks: 4, now: TestFixtures.now)

        XCTAssertEqual(weeks.count, 4)
        XCTAssertTrue(weeks.allSatisfy { $0.meters == 0 && $0.sessions == 0 && $0.averagePaceSecondsPer100m == nil })
        XCTAssertEqual(weeks.map(\.weekStart), weeks.map(\.weekStart).sorted())
    }

    func testSessionWithoutDistanceCountsAsSessionButNotAsMetersOrPace() {
        let workouts = [
            TestFixtures.workout(daysAgo: 1, meters: 1000, seconds: 1800),
            TestFixtures.workout(daysAgo: 2, meters: nil, seconds: 3000)
        ]

        let current = statistics.weeklyVolumes(workouts: workouts, weeks: 1, now: TestFixtures.now)[0]

        XCTAssertEqual(current.sessions, 2)
        XCTAssertEqual(current.meters, 1000)
        XCTAssertEqual(current.averagePaceSecondsPer100m ?? 0, 180, accuracy: 0.001)
    }

    func testWorkoutsOutsideTheWindowAreIgnored() {
        let workouts = [TestFixtures.workout(daysAgo: 70, meters: 1000)]

        let weeks = statistics.weeklyVolumes(workouts: workouts, weeks: 8, now: TestFixtures.now)

        XCTAssertEqual(weeks.reduce(0) { $0 + $1.meters }, 0)
    }

    func testNoWeeksRequestedGivesNothing() {
        XCTAssertTrue(statistics.weeklyVolumes(workouts: [], weeks: 0, now: TestFixtures.now).isEmpty)
    }

    func testPaceSamplesSkipShortAndDistancelessSessionsAndSortOldestFirst() {
        let recent = TestFixtures.workout(daysAgo: 1, meters: 1500, seconds: 2400)   // 160 s/100 m
        let older = TestFixtures.workout(daysAgo: 10, meters: 1000, seconds: 1800)   // 180 s/100 m
        let tooShort = TestFixtures.workout(daysAgo: 3, meters: 150, seconds: 300)
        let noDistance = TestFixtures.workout(daysAgo: 4, meters: nil)
        let outsideWindow = TestFixtures.workout(daysAgo: 60, meters: 1000, seconds: 1800)

        let samples = statistics.paceSamples(
            workouts: [recent, tooShort, noDistance, older, outsideWindow],
            now: TestFixtures.now
        )

        XCTAssertEqual(samples.map(\.id), [older.id, recent.id])
        XCTAssertEqual(samples[0].paceSecondsPer100m, 180, accuracy: 0.001)
        XCTAssertEqual(samples[1].paceSecondsPer100m, 160, accuracy: 0.001)
        XCTAssertEqual(samples[1].distanceMeters, 1500)
    }

    func testPaceSamplesIgnoreWorkoutsInTheFuture() {
        let future = TestFixtures.workout(daysAgo: 0, meters: 1000, seconds: 1800, hour: 20)

        XCTAssertTrue(statistics.paceSamples(workouts: [future], now: TestFixtures.now).isEmpty)
    }
}
