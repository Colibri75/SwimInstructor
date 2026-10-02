import XCTest
@testable import SwimInstructorCore

final class MacroPlanTests: XCTestCase {
    func testDecodesTheServerResponse() throws {
        let response = try PlanResponse.jsonDecoder().decode(MacroPlanResponse.self, from: Data(MacroFixtures.responseJSON.utf8))

        XCTAssertEqual(response.goalDay, "2027-07-04")
        XCTAssertEqual(response.generatedAt, ISO8601DateFormatter().date(from: "2026-09-30T10:00:00Z"))
        XCTAssertEqual(response.adjustments.count, 1)
        XCTAssertEqual(response.plan.rationale, "40 Wochen bis zum Ziel.")
        XCTAssertEqual(response.plan.weeks.count, 5)
        XCTAssertEqual(response.plan.weeks[0], MacroFixtures.week("2026-09-28", meters: 3500, focus: "Ausdauer und Technik"))
        XCTAssertEqual(response.plan.weeks[2].deload, true)
        XCTAssertEqual(response.plan.weeks.map(\.phase), [.base, .base, .base, .taper, .goalWeek])
    }

    func testTheResponseBecomesAStoredPlanForTheGivenGoal() throws {
        let response = try PlanResponse.jsonDecoder().decode(MacroPlanResponse.self, from: Data(MacroFixtures.responseJSON.utf8))

        let plan = response.macroPlan(goalKey: "ziel")

        XCTAssertEqual(plan.goalKey, "ziel")
        XCTAssertEqual(plan.goalDay, "2027-07-04")
        XCTAssertEqual(plan.weeks.count, 5)
        XCTAssertEqual(plan.rationale, "40 Wochen bis zum Ziel.")
        XCTAssertEqual(plan.peakMeters, 3800)
    }

    func testWeeksAreSortedAndFoundByTheirMonday() {
        let plan = MacroFixtures.plan(weeks: [MacroFixtures.week("2026-10-12"), MacroFixtures.week("2026-09-28")])

        XCTAssertEqual(plan.weeks.map(\.weekStart), ["2026-09-28", "2026-10-12"])
        XCTAssertNotNil(plan.week(starting: "2026-10-12"))
        XCTAssertNil(plan.week(starting: "2026-10-05"))
        XCTAssertEqual(plan.weeks(from: "2026-10-01").map(\.weekStart), ["2026-10-12"])
    }

    func testTheGoalKeyChangesWithDistanceTimeAndDay() {
        let base = AthleteGoal.default
        let longer = AthleteGoal(distanceMeters: 5000, targetDurationSeconds: base.targetDurationSeconds, targetDate: base.targetDate)
        let slower = AthleteGoal(distanceMeters: base.distanceMeters, targetDurationSeconds: 4000, targetDate: base.targetDate)
        let later = AthleteGoal(distanceMeters: base.distanceMeters, targetDurationSeconds: base.targetDurationSeconds, targetDate: base.targetDate.addingTimeInterval(86_400 * 3))

        XCTAssertEqual(base.key(calendar: TestFixtures.utc), "3800-3600-2027-07-04")
        XCTAssertEqual(Set([base, longer, slower, later].map { $0.key(calendar: TestFixtures.utc) }).count, 4)
        XCTAssertEqual(base.goalDay(calendar: TestFixtures.utc), "2027-07-04")
    }

    func testThePlanSurvivesEncodingForTheFile() throws {
        let plan = MacroFixtures.plan()

        let decoded = try PlanResponse.jsonDecoder().decode(MacroPlan.self, from: try PlanResponse.jsonEncoder().encode(plan))

        XCTAssertEqual(decoded, plan)
    }

    func testTheFileStoreRoundTripsAndToleratesAMissingOrBrokenFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macro-\(UUID().uuidString)/macro-plan.json")
        let store = FileMacroPlanStore(fileURL: url)
        XCTAssertNil(store.load())

        try store.save(MacroFixtures.plan())
        XCTAssertEqual(store.load(), MacroFixtures.plan())

        try Data("kaputt".utf8).write(to: url)
        XCTAssertNil(store.load())
    }
}
