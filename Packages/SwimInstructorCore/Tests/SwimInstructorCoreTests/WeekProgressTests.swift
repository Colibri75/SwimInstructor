import XCTest
@testable import SwimInstructorCore

final class WeekProgressTests: XCTestCase {
    private let calculator = WeekProgressCalculator(calendar: TestFixtures.utc)
    /// Mittwoch 30.09.2026, 12:00 UTC.
    private let now = TestFixtures.now

    private func statuses(_ plan: WeekPlan?, _ workouts: [SwimWorkout] = []) -> [WeekDayStatus] {
        calculator.statuses(plan: plan, weekStart: WeekFixtures.weekStart, workouts: workouts, now: now)
    }

    private func state(_ date: String, _ plan: WeekPlan?, _ workouts: [SwimWorkout] = []) -> WeekDayState? {
        statuses(plan, workouts).first { $0.date == date }?.state
    }

    /// Plan für die ganze Woche: Mo 1500, Di Ruhe, Mi 1500, Do Ruhe, Fr 1000, Sa 2000, So Ruhe.
    private var fullWeek: WeekPlan {
        WeekFixtures.plan(days: [
            WeekFixtures.day("2026-09-28"),
            WeekFixtures.restDay("2026-09-29"),
            WeekFixtures.day("2026-09-30"),
            WeekFixtures.restDay("2026-10-01"),
            WeekFixtures.day("2026-10-02", WeekFixtures.content(meters: 1000)),
            WeekFixtures.day("2026-10-03", WeekFixtures.content(meters: 2000)),
            WeekFixtures.restDay("2026-10-04")
        ])
    }

    func testAlwaysSevenDaysFromMondayEvenWithoutAPlan() {
        let result = statuses(nil)

        XCTAssertEqual(result.map(\.date), ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
        XCTAssertTrue(result.allSatisfy { $0.state == .unplanned && $0.plan == nil })
    }

    func testPastTrainingDayIsFollowedShorterLongerOrMissed() {
        let plan = fullWeek

        XCTAssertEqual(state("2026-09-28", plan, [TestFixtures.workout(daysAgo: 2, meters: 1500)]), .followed)
        XCTAssertEqual(state("2026-09-28", plan, [TestFixtures.workout(daysAgo: 2, meters: 1125)]), .followed)
        XCTAssertEqual(state("2026-09-28", plan, [TestFixtures.workout(daysAgo: 2, meters: 1124)]), .shorter)
        XCTAssertEqual(state("2026-09-28", plan, [TestFixtures.workout(daysAgo: 2, meters: 1875)]), .followed)
        XCTAssertEqual(state("2026-09-28", plan, [TestFixtures.workout(daysAgo: 2, meters: 1876)]), .longer)
        XCTAssertEqual(state("2026-09-28", plan), .missed)
    }

    func testPastRestDayIsKeptOrBroken() {
        let plan = fullWeek

        XCTAssertEqual(state("2026-09-29", plan), .restKept)
        XCTAssertEqual(state("2026-09-29", plan, [TestFixtures.workout(daysAgo: 1, meters: 600)]), .restBroken)
    }

    func testTodayStaysOpenUntilEnoughWasSwum() {
        let plan = fullWeek

        XCTAssertEqual(state("2026-09-30", plan), .today)
        XCTAssertEqual(state("2026-09-30", plan, [TestFixtures.workout(daysAgo: 0, meters: 400, hour: 8)]), .today)
        XCTAssertEqual(state("2026-09-30", plan, [TestFixtures.workout(daysAgo: 0, meters: 1500, hour: 8)]), .followed)
        XCTAssertEqual(state("2026-09-30", plan, [TestFixtures.workout(daysAgo: 0, meters: 2500, hour: 8)]), .longer)
    }

    func testTodayRestDay() {
        let plan = WeekFixtures.plan(days: [WeekFixtures.restDay("2026-09-30")])

        XCTAssertEqual(state("2026-09-30", plan), .today)
        XCTAssertEqual(state("2026-09-30", plan, [TestFixtures.workout(daysAgo: 0, meters: 500, hour: 8)]), .restBroken)
    }

    func testFutureDaysAreUpcoming() {
        XCTAssertEqual(state("2026-10-02", fullWeek), .upcoming)
        XCTAssertEqual(state("2026-10-04", fullWeek), .upcoming)
    }

    func testDaysWithoutTimeAreSkipped() {
        let plan = WeekPlanEditor.markUnavailable(fullWeek, date: "2026-09-28")

        XCTAssertEqual(state("2026-09-28", plan), .skipped)
        XCTAssertEqual(state("2026-09-28", plan, [TestFixtures.workout(daysAgo: 2, meters: 900)]), .skipped)
        XCTAssertEqual(state("2026-10-02", WeekPlanEditor.markUnavailable(fullWeek, date: "2026-10-02")), .skipped)
    }

    func testDaysWithoutAnEntryAreUnplannedButShowWhatWasSwum() {
        let plan = WeekFixtures.plan()
        let status = statuses(plan, [TestFixtures.workout(daysAgo: 2, meters: 1200)]).first { $0.date == "2026-09-28" }

        XCTAssertEqual(status?.state, .unplanned)
        XCTAssertEqual(status?.actualMeters, 1200)
        XCTAssertEqual(status?.workoutCount, 1)
    }

    func testSeveralWorkoutsOfOneDayAreAdded() {
        let workouts = [TestFixtures.workout(daysAgo: 2, meters: 700, hour: 7), TestFixtures.workout(daysAgo: 2, meters: 800, hour: 18)]
        let status = statuses(fullWeek, workouts).first { $0.date == "2026-09-28" }

        XCTAssertEqual(status?.actualMeters, 1500)
        XCTAssertEqual(status?.workoutCount, 2)
        XCTAssertEqual(status?.state, .followed)
    }

    func testWorkoutWithoutDistanceCountsAsDoneButIsNotCompared() {
        XCTAssertEqual(state("2026-09-28", fullWeek, [TestFixtures.workout(daysAgo: 2, meters: nil)]), .followed)
    }

    func testWorkoutsInTheFutureAreIgnored() {
        XCTAssertEqual(state("2026-09-30", fullWeek, [TestFixtures.workout(daysAgo: 0, meters: 1500, hour: 20)]), .today)
    }

    func testSummaryCountsPlannedAndSwumMetersAndSessions() {
        let workouts = [
            TestFixtures.workout(daysAgo: 2, meters: 1500),          // Mo erledigt
            TestFixtures.workout(daysAgo: 0, meters: 1200, hour: 8)  // Mi: 1200 von 1500 = 80 %
        ]

        let summary = calculator.summary(of: statuses(fullWeek, workouts))

        XCTAssertEqual(summary.plannedMeters, 6000)
        XCTAssertEqual(summary.swumMeters, 2700)
        XCTAssertEqual(summary.sessionsPlanned, 4)
        XCTAssertEqual(summary.sessionsDue, 2)
        XCTAssertEqual(summary.sessionsDone, 2)
    }

    func testSummaryCountsAMissedSessionAsDueButNotDone() {
        let summary = calculator.summary(of: statuses(fullWeek))

        XCTAssertEqual(summary.sessionsDue, 1)
        XCTAssertEqual(summary.sessionsDone, 0)
        XCTAssertEqual(summary.sessionsPlanned, 4)
    }

    func testSummaryLeavesOutDaysWithoutTime() {
        let plan = WeekPlanEditor.markUnavailable(fullWeek, date: "2026-10-03")

        let summary = calculator.summary(of: statuses(plan))

        XCTAssertEqual(summary.plannedMeters, 4000)
        XCTAssertEqual(summary.sessionsPlanned, 3)
    }

    func testSummaryWithoutAPlanOnlyCountsWhatWasSwum() {
        let summary = calculator.summary(of: statuses(nil, [TestFixtures.workout(daysAgo: 1, meters: 800)]))

        XCTAssertEqual(summary, WeekSummary(plannedMeters: 0, swumMeters: 800, sessionsDue: 0, sessionsDone: 0, sessionsPlanned: 0))
    }
}
