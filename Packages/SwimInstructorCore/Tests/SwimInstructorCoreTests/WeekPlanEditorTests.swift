import XCTest
@testable import SwimInstructorCore

final class WeekPlanEditorTests: XCTestCase {
    private let base = WeekFixtures.plan()

    // MARK: - Keine Zeit

    func testUnavailableDayBecomesARestDayAndRemembersTheSession() {
        let plan = WeekPlanEditor.markUnavailable(base, date: "2026-10-02")

        let day = plan.day(on: "2026-10-02")
        XCTAssertEqual(day?.isUnavailable, true)
        XCTAssertEqual(day?.isRestDay, true)
        XCTAssertEqual(day?.focus, "Keine Zeit")
        XCTAssertEqual(day?.contentBeforeUnavailable?.targetDistanceMeters, 1000)
        XCTAssertEqual(day?.isEdited, true)
    }

    func testUnavailableOnARestDayRemembersNothing() {
        let plan = WeekPlanEditor.markUnavailable(base, date: "2026-10-01")

        XCTAssertNil(plan.day(on: "2026-10-01")?.contentBeforeUnavailable)
        XCTAssertEqual(plan.day(on: "2026-10-01")?.isUnavailable, true)
    }

    func testMarkingTwiceKeepsTheFirstMemory() {
        let once = WeekPlanEditor.markUnavailable(base, date: "2026-10-02")
        let twice = WeekPlanEditor.markUnavailable(once, date: "2026-10-02")

        XCTAssertEqual(twice, once)
    }

    func testClearingUnavailableBringsTheSessionBack() {
        let marked = WeekPlanEditor.markUnavailable(base, date: "2026-10-02")

        let cleared = WeekPlanEditor.clearUnavailable(marked, date: "2026-10-02")

        let day = cleared.day(on: "2026-10-02")
        XCTAssertEqual(day?.isUnavailable, false)
        XCTAssertEqual(day?.targetDistanceMeters, 1000)
        XCTAssertEqual(day?.sessionType, .technique)
        XCTAssertNil(day?.contentBeforeUnavailable)
    }

    func testClearingWithoutMemoryLeavesARestDay() {
        let cleared = WeekPlanEditor.clearUnavailable(WeekPlanEditor.markUnavailable(base, date: "2026-10-01"), date: "2026-10-01")

        XCTAssertEqual(cleared.day(on: "2026-10-01")?.isUnavailable, false)
        XCTAssertEqual(cleared.day(on: "2026-10-01")?.isRestDay, true)
    }

    func testClearingADayThatIsAvailableChangesNothing() {
        XCTAssertEqual(WeekPlanEditor.clearUnavailable(base, date: "2026-10-02"), base)
    }

    func testAnUnplannedDayCanBeMarkedAndIsCreatedForIt() {
        let plan = WeekPlanEditor.markUnavailable(base, date: "2026-09-29")

        XCTAssertEqual(plan.day(on: "2026-09-29")?.isUnavailable, true)
        XCTAssertEqual(plan.days.map(\.date), ["2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
    }

    // MARK: - Ruhetag und Umfang

    func testSetRestMakesARestDayButNotOnAnUnavailableDay() {
        let rest = WeekPlanEditor.setRest(base, date: "2026-10-03")
        XCTAssertEqual(rest.day(on: "2026-10-03")?.isRestDay, true)
        XCTAssertEqual(rest.day(on: "2026-10-03")?.focus, "Ruhetag")

        let marked = WeekPlanEditor.markUnavailable(base, date: "2026-10-03")
        XCTAssertEqual(WeekPlanEditor.setRest(marked, date: "2026-10-03"), marked)
    }

    func testSetDistanceScalesTheDurationAndKeepsTheSession() {
        let plan = WeekPlanEditor.setDistance(base, date: "2026-10-03", meters: 1000)

        let day = plan.day(on: "2026-10-03")
        XCTAssertEqual(day?.targetDistanceMeters, 1000)
        XCTAssertEqual(day?.estimatedDurationMinutes, 28)
        XCTAssertEqual(day?.sessionType, .threshold)
        XCTAssertEqual(day?.isEdited, true)
    }

    func testZeroMetersMakeARestDay() {
        let day = WeekPlanEditor.setDistance(base, date: "2026-10-03", meters: 0).day(on: "2026-10-03")

        XCTAssertEqual(day?.isRestDay, true)
        XCTAssertEqual(day?.targetDistanceMeters, 0)
        XCTAssertEqual(day?.estimatedDurationMinutes, 0)
    }

    func testMetersOnARestDayCreateAnEasyEnduranceSession() {
        let day = WeekPlanEditor.setDistance(base, date: "2026-10-01", meters: 800).day(on: "2026-10-01")

        XCTAssertEqual(day?.sessionType, .endurance)
        XCTAssertEqual(day?.intensity, .easy)
        XCTAssertEqual(day?.targetDistanceMeters, 800)
        XCTAssertEqual(day?.estimatedDurationMinutes, 20)
        XCTAssertEqual(day?.isRestDay, false)
    }

    func testDistanceIsClampedToTheAllowedRange() {
        XCTAssertEqual(WeekPlanEditor.setDistance(base, date: "2026-10-03", meters: 99_999).day(on: "2026-10-03")?.targetDistanceMeters, WeekPlanEditor.maxDistanceMeters)
        XCTAssertEqual(WeekPlanEditor.setDistance(base, date: "2026-10-03", meters: -50).day(on: "2026-10-03")?.isRestDay, true)
    }

    func testDistanceOfAnUnavailableDayDoesNotChange() {
        let marked = WeekPlanEditor.markUnavailable(base, date: "2026-10-03")

        XCTAssertEqual(WeekPlanEditor.setDistance(marked, date: "2026-10-03", meters: 1500), marked)
    }

    // MARK: - Tauschen und Verschieben

    func testSwapExchangesTheContentOfTwoDays() {
        let plan = WeekPlanEditor.swap(base, "2026-09-30", "2026-10-03")

        XCTAssertEqual(plan.day(on: "2026-09-30")?.sessionType, .threshold)
        XCTAssertEqual(plan.day(on: "2026-09-30")?.targetDistanceMeters, 2000)
        XCTAssertEqual(plan.day(on: "2026-10-03")?.sessionType, .endurance)
        XCTAssertEqual(plan.day(on: "2026-10-03")?.targetDistanceMeters, 1500)
        XCTAssertEqual(plan.day(on: "2026-09-30")?.isEdited, true)
        XCTAssertEqual(plan.day(on: "2026-10-03")?.isEdited, true)
        XCTAssertEqual(plan.plannedMeters, base.plannedMeters)
    }

    func testSwapWithARestDayMovesTheSessionThere() {
        let plan = WeekPlanEditor.swap(base, "2026-10-02", "2026-10-04")

        XCTAssertEqual(plan.day(on: "2026-10-02")?.isRestDay, true)
        XCTAssertEqual(plan.day(on: "2026-10-04")?.sessionType, .technique)
    }

    func testSwapWithTheSameDayOrAnUnavailableDayChangesNothing() {
        XCTAssertEqual(WeekPlanEditor.swap(base, "2026-10-02", "2026-10-02"), base)

        let marked = WeekPlanEditor.markUnavailable(base, date: "2026-10-04")
        XCTAssertEqual(WeekPlanEditor.swap(marked, "2026-10-02", "2026-10-04"), marked)
    }

    func testMovingAMissedSessionToARestDay() {
        let withMissed = WeekFixtures.plan(days: [WeekFixtures.day("2026-09-29"), WeekFixtures.restDay("2026-10-01")] + Array(base.days.dropFirst(2)))

        let plan = WeekPlanEditor.moveToRestDay(withMissed, from: "2026-09-29", to: "2026-10-01")

        XCTAssertEqual(plan.day(on: "2026-10-01")?.sessionType, .endurance)
        XCTAssertEqual(plan.day(on: "2026-10-01")?.targetDistanceMeters, 1500)
        XCTAssertEqual(plan.day(on: "2026-09-29")?.isRestDay, true)
        XCTAssertEqual(plan.day(on: "2026-09-29")?.focus, "Verschoben")
    }

    func testMovingOntoATrainingDayOrFromARestDayChangesNothing() {
        XCTAssertEqual(WeekPlanEditor.moveToRestDay(base, from: "2026-09-30", to: "2026-10-02"), base)
        XCTAssertEqual(WeekPlanEditor.moveToRestDay(base, from: "2026-10-01", to: "2026-10-04"), base)
        XCTAssertEqual(WeekPlanEditor.moveToRestDay(base, from: "2026-09-30", to: "2026-09-30"), base)
        XCTAssertEqual(WeekPlanEditor.moveToRestDay(base, from: "2026-09-30", to: "2026-09-25"), base)
    }

    func testMovingOntoARestDayWithoutTimeChangesNothing() {
        let marked = WeekPlanEditor.markUnavailable(base, date: "2026-10-04")

        XCTAssertEqual(WeekPlanEditor.moveToRestDay(marked, from: "2026-09-30", to: "2026-10-04"), marked)
    }

    // MARK: - Neu geplant übernehmen

    func testMergeKeepsPastDaysAndReplacesFromTheStartDate() {
        let old = WeekFixtures.plan(days: [
            WeekFixtures.day("2026-09-28", WeekFixtures.content(meters: 1200)),
            WeekFixtures.day("2026-09-29", WeekFixtures.content(meters: 900)),
            WeekFixtures.day("2026-09-30", WeekFixtures.content(meters: 1500)),
            WeekFixtures.restDay("2026-10-01")
        ])
        let new = WeekFixtures.plan(days: [WeekFixtures.day("2026-09-30", WeekFixtures.content(meters: 700)), WeekFixtures.day("2026-10-01", WeekFixtures.content(meters: 800))])

        let merged = WeekPlanEditor.merge(existing: old, generated: new, fromDate: "2026-09-30")

        XCTAssertEqual(merged.days.map(\.date), ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"])
        XCTAssertEqual(merged.days.map(\.targetDistanceMeters), [1200, 900, 700, 800])
    }

    func testMergeKeepsDaysWithoutTimeEvenIfTheServerPlannedThem() {
        let old = WeekPlanEditor.markUnavailable(base, date: "2026-10-02")
        let new = WeekFixtures.plan(days: [WeekFixtures.day("2026-09-30"), WeekFixtures.day("2026-10-02", WeekFixtures.content(meters: 1800))])

        let merged = WeekPlanEditor.merge(existing: old, generated: new, fromDate: "2026-09-30")

        XCTAssertEqual(merged.day(on: "2026-10-02")?.isUnavailable, true)
        XCTAssertEqual(merged.day(on: "2026-10-02")?.targetDistanceMeters, 0)
        XCTAssertEqual(merged.day(on: "2026-10-02")?.contentBeforeUnavailable?.targetDistanceMeters, 1000)
    }

    func testMergeDropsOldDaysFromTheStartDateOn() {
        let new = WeekFixtures.plan(days: [WeekFixtures.day("2026-09-30")])

        let merged = WeekPlanEditor.merge(existing: base, generated: new, fromDate: "2026-09-30")

        XCTAssertEqual(merged.days.map(\.date), ["2026-09-30"])
    }

    func testMergeWithoutAnExistingPlanOrAnotherWeekTakesTheNewOne() {
        let new = WeekFixtures.plan(days: [WeekFixtures.day("2026-09-30")])
        var other = base
        other.weekStart = "2026-09-21"

        XCTAssertEqual(WeekPlanEditor.merge(existing: nil, generated: new, fromDate: "2026-09-30"), new)
        XCTAssertEqual(WeekPlanEditor.merge(existing: other, generated: new, fromDate: "2026-09-30"), new)
    }

    func testMergeTakesRationaleAdjustmentsAndWishFromTheNewPlan() {
        var new = WeekFixtures.plan(days: [WeekFixtures.day("2026-09-30")])
        new.rationale = "Neu"
        new.adjustments = ["x"]
        new.wishes = "w"

        let merged = WeekPlanEditor.merge(existing: base, generated: new, fromDate: "2026-09-30")

        XCTAssertEqual(merged.rationale, "Neu")
        XCTAssertEqual(merged.adjustments, ["x"])
        XCTAssertEqual(merged.wishes, "w")
    }

    // MARK: - Rollender Plan (Zusammenführen bis zum Ende des Fensters)

    func testMergeWithAWindowKeepsOldDaysBeyondItThatTheNewPlanDoesNotKnow() {
        let old = WeekFixtures.plan()
        let new = WeekFixtures.plan(days: [WeekFixtures.day("2026-09-30", WeekFixtures.content(meters: 700)), WeekFixtures.day("2026-10-01", WeekFixtures.content(meters: 800))])

        // Das Fenster endet am 01.10.: 02.-04.10. stammen aus dem Plan davor.
        let merged = WeekPlanEditor.merge(existing: old, generated: new, fromDate: "2026-09-30", through: "2026-10-01")

        XCTAssertEqual(merged.days.map(\.date), ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
        XCTAssertEqual(merged.days.map(\.targetDistanceMeters), [700, 800, 1000, 2000, 0])
    }

    func testMergeWithAWindowStillTakesTheNewPlanInsideTheWindowAndKeepsThePast() {
        let past = WeekFixtures.day("2026-09-28", WeekFixtures.content(meters: 1234))
        let old = WeekFixtures.plan(days: [past] + WeekFixtures.plan().days)
        let new = WeekFixtures.plan(days: [WeekFixtures.day("2026-09-30", WeekFixtures.content(meters: 700))])

        let merged = WeekPlanEditor.merge(existing: old, generated: new, fromDate: "2026-09-30", through: "2026-10-06")

        XCTAssertEqual(merged.days.map(\.date), ["2026-09-28", "2026-09-30"])
        XCTAssertEqual(merged.days.first?.targetDistanceMeters, 1234)
    }

    func testMergeWithAWindowKeepsADayWithoutTimeBeyondIt() {
        let old = WeekPlanEditor.markUnavailable(base, date: "2026-10-04")
        let new = WeekFixtures.plan(days: [WeekFixtures.day("2026-09-30")])

        let merged = WeekPlanEditor.merge(existing: old, generated: new, fromDate: "2026-09-30", through: "2026-09-30")

        XCTAssertEqual(merged.day(on: "2026-10-04")?.isUnavailable, true)
    }
}

