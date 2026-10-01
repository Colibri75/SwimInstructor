import XCTest
@testable import SwimInstructorCore

final class PlanAdherenceTests: XCTestCase {
    private let calculator = PlanAdherenceCalculator(calendar: TestFixtures.utc)

    private func day(_ daysAgo: Int) -> String {
        PlanFormatting.isoDay(TestFixtures.date(daysAgo: daysAgo, hour: 12), calendar: TestFixtures.utc)
    }

    private func plan(daysAgo: Int, type: SessionType = .endurance, meters: Int = 1600) -> PlanResponse {
        PlanResponse(
            source: .claude,
            date: day(daysAgo),
            generatedAt: TestFixtures.now,
            stale: false,
            plan: TrainingPlan(
                sessionType: type,
                intensity: type == .rest ? .rest : .moderate,
                rationale: "Test",
                totalDistanceMeters: meters,
                estimatedDurationMinutes: 40,
                sets: [],
                coachNotes: []
            ),
            adjustments: []
        )
    }

    private func outcome(plan: PlanResponse, workouts: [SwimWorkout]) -> AdherenceOutcome? {
        calculator.entries(plans: [plan], workouts: workouts, now: TestFixtures.now).first?.outcome
    }

    func testPlannedDistanceReachedCountsAsFollowed() {
        let result = outcome(plan: plan(daysAgo: 2), workouts: [TestFixtures.workout(daysAgo: 2, meters: 1500)])
        XCTAssertEqual(result, .followed)
    }

    func testToleranceBoundariesAreInclusive() {
        XCTAssertEqual(outcome(plan: plan(daysAgo: 2, meters: 1000), workouts: [TestFixtures.workout(daysAgo: 2, meters: 750)]), .followed)
        XCTAssertEqual(outcome(plan: plan(daysAgo: 2, meters: 1000), workouts: [TestFixtures.workout(daysAgo: 2, meters: 1250)]), .followed)
        XCTAssertEqual(outcome(plan: plan(daysAgo: 2, meters: 1000), workouts: [TestFixtures.workout(daysAgo: 2, meters: 749)]), .shorter)
        XCTAssertEqual(outcome(plan: plan(daysAgo: 2, meters: 1000), workouts: [TestFixtures.workout(daysAgo: 2, meters: 1251)]), .longer)
    }

    func testTrainingDayWithoutSwimmingIsMissed() {
        XCTAssertEqual(outcome(plan: plan(daysAgo: 2), workouts: []), .missed)
    }

    func testRestDayKeptAndBroken() {
        let rest = plan(daysAgo: 2, type: .rest, meters: 0)
        XCTAssertEqual(outcome(plan: rest, workouts: []), .restKept)
        XCTAssertEqual(outcome(plan: rest, workouts: [TestFixtures.workout(daysAgo: 2, meters: 800)]), .restBroken)
    }

    func testTodayStaysPendingUntilTheDayIsOver() {
        XCTAssertEqual(outcome(plan: plan(daysAgo: 0), workouts: []), .pending)
        XCTAssertEqual(outcome(plan: plan(daysAgo: 0, type: .rest, meters: 0), workouts: []), .pending)
        // Erst 400 von 1600 m: Es kann noch etwas folgen.
        XCTAssertEqual(outcome(plan: plan(daysAgo: 0), workouts: [TestFixtures.workout(daysAgo: 0, meters: 400)]), .pending)
        XCTAssertEqual(outcome(plan: plan(daysAgo: 0), workouts: [TestFixtures.workout(daysAgo: 0, meters: 1600)]), .followed)
        XCTAssertEqual(outcome(plan: plan(daysAgo: 0, type: .rest, meters: 0), workouts: [TestFixtures.workout(daysAgo: 0, meters: 500)]), .restBroken)
    }

    func testSeveralWorkoutsOfTheSameDayAreAdded() throws {
        let workouts = [
            TestFixtures.workout(daysAgo: 2, meters: 800, hour: 7),
            TestFixtures.workout(daysAgo: 2, meters: 700, hour: 18)
        ]

        let entry = try XCTUnwrap(calculator.entries(plans: [plan(daysAgo: 2)], workouts: workouts, now: TestFixtures.now).first)

        XCTAssertEqual(entry.actualMeters, 1500)
        XCTAssertEqual(entry.workoutCount, 2)
        XCTAssertEqual(entry.plannedMeters, 1600)
        XCTAssertEqual(entry.outcome, .followed)
    }

    func testWorkoutOnAnotherDayDoesNotCount() {
        XCTAssertEqual(outcome(plan: plan(daysAgo: 2), workouts: [TestFixtures.workout(daysAgo: 3, meters: 1600)]), .missed)
    }

    func testWorkoutWithoutDistanceCountsAsTrainedButIsNotCompared() throws {
        let entry = try XCTUnwrap(
            calculator.entries(plans: [plan(daysAgo: 2)], workouts: [TestFixtures.workout(daysAgo: 2, meters: nil)], now: TestFixtures.now).first
        )

        XCTAssertEqual(entry.outcome, .followed)
        XCTAssertEqual(entry.workoutCount, 1)
        XCTAssertEqual(entry.actualMeters, 0)
    }

    func testEntriesAreNewestFirstAndLimitedToTheWindow() {
        let plans = [plan(daysAgo: 40), plan(daysAgo: 27), plan(daysAgo: 5), plan(daysAgo: 0)]

        let entries = calculator.entries(plans: plans, workouts: [], days: 28, now: TestFixtures.now)

        XCTAssertEqual(entries.map(\.date), [day(0), day(5), day(27)])
    }

    func testPlansInTheFutureAreIgnored() {
        XCTAssertTrue(calculator.entries(plans: [plan(daysAgo: -1)], workouts: [], now: TestFixtures.now).isEmpty)
    }

    func testSummaryCountsFinishedDaysOnly() {
        let plans = [
            plan(daysAgo: 6),                          // geschwommen, passend
            plan(daysAgo: 5),                          // geschwommen, zu kurz
            plan(daysAgo: 4),                          // verpasst
            plan(daysAgo: 3, type: .rest, meters: 0),  // Ruhetag eingehalten
            plan(daysAgo: 2, type: .rest, meters: 0),  // Ruhetag gebrochen
            plan(daysAgo: 0)                           // heute, offen
        ]
        let workouts = [
            TestFixtures.workout(daysAgo: 6, meters: 1600),
            TestFixtures.workout(daysAgo: 5, meters: 500),
            TestFixtures.workout(daysAgo: 2, meters: 600)
        ]

        let entries = calculator.entries(plans: plans, workouts: workouts, now: TestFixtures.now)
        let summary = calculator.summary(of: entries)

        XCTAssertEqual(entries.map(\.outcome), [.pending, .restBroken, .restKept, .missed, .shorter, .followed])
        XCTAssertEqual(summary, PlanAdherenceSummary(plannedTrainingDays: 3, trainedDays: 2, restDays: 2, restDaysKept: 1))
    }

    func testSummaryOfNothingIsZero() {
        XCTAssertEqual(
            calculator.summary(of: []),
            PlanAdherenceSummary(plannedTrainingDays: 0, trainedDays: 0, restDays: 0, restDaysKept: 0)
        )
    }
}
