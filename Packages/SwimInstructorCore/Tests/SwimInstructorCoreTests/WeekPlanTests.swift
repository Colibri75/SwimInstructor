import XCTest
@testable import SwimInstructorCore

final class WeekPlanTests: XCTestCase {
    func testDecodesTheServerResponseIntoAWeekPlan() throws {
        let response = try PlanResponse.jsonDecoder().decode(WeekPlanResponse.self, from: Data(WeekFixtures.responseJSON.utf8))
        let plan = response.weekPlan

        XCTAssertEqual(plan.weekStart, "2026-09-28")
        XCTAssertEqual(plan.generatedAt, TestFixtures.now.addingTimeInterval(-2 * 3600))
        XCTAssertEqual(plan.rationale, "Solide Woche.")
        XCTAssertEqual(plan.adjustments, ["Samstag: harte Einheit gesenkt"])
        XCTAssertEqual(plan.wishes, "mehr Technik")
        XCTAssertEqual(plan.days.map(\.date), ["2026-09-30", "2026-10-01", "2026-10-02"])
        XCTAssertEqual(plan.days[0].sessionType, .endurance)
        XCTAssertEqual(plan.days[2].focus, "Technik mit Pull Buoy")
        XCTAssertTrue(plan.days[1].isRestDay)
        XCTAssertEqual(response.plan.totalDistanceMeters, 2500)
    }

    func testServerDaysStartWithoutMarksOfTheAthlete() throws {
        let plan = try PlanResponse.jsonDecoder().decode(WeekPlanResponse.self, from: Data(WeekFixtures.responseJSON.utf8)).weekPlan

        XCTAssertTrue(plan.days.allSatisfy { !$0.isUnavailable && !$0.isEdited && $0.contentBeforeUnavailable == nil })
    }

    func testUnknownTypesFallBackToUnknown() throws {
        let json = WeekFixtures.responseJSON.replacingOccurrences(of: "\"technique\"", with: "\"wandern\"")

        let plan = try PlanResponse.jsonDecoder().decode(WeekPlanResponse.self, from: Data(json.utf8)).weekPlan

        XCTAssertEqual(plan.days[2].sessionType, .unknown)
    }

    func testWeekPlanSurvivesStoringWithAllMarks() throws {
        var plan = WeekFixtures.plan()
        plan = WeekPlanEditor.markUnavailable(plan, date: "2026-10-02")
        plan = WeekPlanEditor.swap(plan, "2026-09-30", "2026-10-03")
        plan.wishes = "weniger Umfang"

        let data = try PlanResponse.jsonEncoder().encode(plan)
        let decoded = try PlanResponse.jsonDecoder().decode(WeekPlan.self, from: data)

        XCTAssertEqual(decoded, plan)
        XCTAssertTrue(decoded.day(on: "2026-10-02")?.isUnavailable == true)
        XCTAssertEqual(decoded.day(on: "2026-10-02")?.contentBeforeUnavailable?.focus, "Technik")
        XCTAssertTrue(decoded.day(on: "2026-09-30")?.isEdited == true)
    }

    func testDaysAreKeptSortedByDate() {
        let plan = WeekFixtures.plan(days: [WeekFixtures.day("2026-10-03"), WeekFixtures.day("2026-09-30"), WeekFixtures.day("2026-10-01")])

        XCTAssertEqual(plan.days.map(\.date), ["2026-09-30", "2026-10-01", "2026-10-03"])
    }

    func testPlannedMetersLeaveOutDaysWithoutTime() {
        var plan = WeekFixtures.plan()
        XCTAssertEqual(plan.plannedMeters, 4500)

        plan = WeekPlanEditor.markUnavailable(plan, date: "2026-10-03")

        XCTAssertEqual(plan.plannedMeters, 2500)
    }

    func testDayLookupAndRestFlag() {
        let plan = WeekFixtures.plan()

        XCTAssertNil(plan.day(on: "2026-09-28"))
        XCTAssertEqual(plan.day(on: "2026-10-02")?.targetDistanceMeters, 1000)
        XCTAssertTrue(plan.day(on: "2026-10-01")?.isRestDay == true)
        XCTAssertFalse(plan.day(on: "2026-10-03")?.isRestDay == true)
    }

    func testTargetCarriesTheDayForTheServer() {
        let target = WeekFixtures.plan().day(on: "2026-10-02")?.target

        XCTAssertEqual(target, DayPlanTarget(sessionType: .technique, intensity: .easy, targetDistanceMeters: 1000, focus: "Technik"))
    }

    func testContentWithZeroMetersCountsAsRest() {
        XCTAssertTrue(WeekFixtures.content(.endurance, .moderate, meters: 0).isRestDay)
        XCTAssertTrue(WeekFixtures.content(.rest, .rest, meters: 0).isRestDay)
        XCTAssertFalse(WeekFixtures.content().isRestDay)
    }
}
