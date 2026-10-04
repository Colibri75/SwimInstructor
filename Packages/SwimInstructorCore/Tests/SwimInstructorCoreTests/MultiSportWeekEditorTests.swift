import XCTest
@testable import SwimInstructorCore

final class MultiSportWeekEditorTests: XCTestCase {
    // MARK: - Daten

    private static let plannedRunTest = PlannedTest(
        id: "threshold_30min", displayName: "30-Minuten-Test", maximalEffort: true,
        produces: [.thresholdHeartRate, .thresholdPacePerKilometer]
    )

    private static func swimSession(_ meters: Double = 1500, minutes: Double = 40) -> WeekSession {
        WeekSession(
            sport: .swim, sessionType: .endurance, intensity: .moderate, amount: meters, unit: .meters,
            minutes: minutes, distanceMeters: meters, focus: "Ausdauer"
        )
    }

    private static func bikeSession(_ minutes: Double = 60, meters: Double = 25_000) -> WeekSession {
        WeekSession(
            sport: .bike, sessionType: .endurance, intensity: .easy, amount: minutes, unit: .minutes,
            minutes: minutes, distanceMeters: meters, focus: "Grundlage"
        )
    }

    private static func runSession(_ minutes: Double = 20, meters: Double = 3_500) -> WeekSession {
        WeekSession(
            sport: .run, sessionType: .endurance, intensity: .easy, amount: minutes, unit: .minutes,
            minutes: minutes, distanceMeters: meters, focus: "Locker"
        )
    }

    private static func thresholdTestSession() -> WeekSession {
        WeekSession(
            sport: .run, sessionType: .test, intensity: .hard, amount: 50, unit: .minutes,
            minutes: 50, distanceMeters: 9_000, focus: "30-Minuten-Test", test: plannedRunTest
        )
    }

    private static func day(_ date: String, _ focus: String, _ sessions: [WeekSession], isEdited: Bool = false) -> PlannedDay {
        PlannedDay(date: date, content: PlannedDayContent(focus: focus, sessions: sessions), isEdited: isEdited)
    }

    private static func restDay(_ date: String) -> PlannedDay {
        PlannedDay(date: date, content: .rest())
    }

    /// Mi Schwimmen, Do Ruhe, Fr Rad und Laufen, Sa Lauftest, So Ruhe (ab Mittwoch geplant).
    private static func plan(_ days: [PlannedDay]? = nil) -> WeekPlanV2 {
        WeekPlanV2(
            weekStart: "2026-09-28",
            generatedAt: TestFixtures.now,
            rationale: "Test",
            days: days ?? [
                day("2026-09-30", "Schwimmen Ausdauer", [swimSession()]),
                restDay("2026-10-01"),
                day("2026-10-02", "Koppeltraining", [bikeSession(), runSession()]),
                day("2026-10-03", "Leistungstest", [thresholdTestSession()]),
                restDay("2026-10-04")
            ]
        )
    }

    private let base: WeekPlanV2 = MultiSportWeekEditorTests.plan()

    // MARK: - Bereich und Schrittweite

    func testManualRangeAndStepDependOnTheUnit() {
        let metersRange: ClosedRange<Double> = 0...6000
        let minutesRange: ClosedRange<Double> = 0...360
        XCTAssertEqual(MultiSportWeekEditor.manualRange(for: .meters), metersRange)
        XCTAssertEqual(MultiSportWeekEditor.manualRange(for: .minutes), minutesRange)
        XCTAssertEqual(MultiSportWeekEditor.amountStep(for: .meters), 100)
        XCTAssertEqual(MultiSportWeekEditor.amountStep(for: .minutes), 5)
        XCTAssertEqual(MultiSportWeekEditor.maxSessionsPerDay, 2)
    }

    func testConversionHelpers() {
        // Schwimmen 0,8 m/s: 1000 m ≈ 21 min.
        let swim = MultiSportWeekEditor.convert(1000, unit: .meters, speed: 0.8)
        XCTAssertEqual(swim.minutes, 21)
        XCTAssertEqual(swim.meters, 1000)
        // Laufen 2,8 m/s: 30 min = 5040 m.
        let running = MultiSportWeekEditor.convert(30, unit: .minutes, speed: 2.8)
        XCTAssertEqual(running.minutes, 30)
        XCTAssertEqual(running.meters, 5040)

        XCTAssertEqual(MultiSportWeekEditor.rounded(2880, unit: .meters), 2900)
        XCTAssertEqual(MultiSportWeekEditor.rounded(33, unit: .minutes), 35)
        XCTAssertEqual(MultiSportWeekEditor.rounded(2, unit: .minutes), 5)
        XCTAssertEqual(MultiSportWeekEditor.rounded(0, unit: .meters), 100)

        XCTAssertEqual(MultiSportWeekEditor.speed(of: .run, registry: .standard), 2.8)
        XCTAssertEqual(MultiSportWeekEditor.speed(of: "kayak", registry: .standard), 2)
    }

    func testFreshPlanHasNoEditedDays() {
        XCTAssertEqual(base.days.map(\.isEdited), [false, false, false, false, false])
        XCTAssertEqual(base.days.map(\.isUnavailable), [false, false, false, false, false])
        XCTAssertEqual(base.plannedMinutes, 170)
    }

    // MARK: - Keine Zeit

    func testUnavailableDayBecomesARestDayAndRemembersItsSessions() throws {
        let plan = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-02")

        let day = try XCTUnwrap(plan.day(on: "2026-10-02"))
        XCTAssertTrue(day.isUnavailable)
        XCTAssertTrue(day.isRestDay)
        XCTAssertEqual(day.focus, "Keine Zeit")
        XCTAssertTrue(day.isEdited)
        let before = try XCTUnwrap(day.contentBeforeUnavailable)
        XCTAssertEqual(before, PlannedDayContent(focus: "Koppeltraining", sessions: [Self.bikeSession(), Self.runSession()]))
        XCTAssertTrue(day.target.sessions.isEmpty)
        // Ohne Zeit zählt der Tag nicht zur geplanten Zeit der Woche.
        XCTAssertEqual(plan.plannedMinutes, 90)
    }

    func testUnavailableOnARestDayRemembersNothing() throws {
        let day = try XCTUnwrap(MultiSportWeekEditor.markUnavailable(base, date: "2026-10-01").day(on: "2026-10-01"))

        XCTAssertTrue(day.isUnavailable)
        XCTAssertNil(day.contentBeforeUnavailable)
        XCTAssertTrue(day.isEdited)
    }

    func testMarkingTwiceKeepsTheFirstMemory() {
        let once = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-02")

        XCTAssertEqual(MultiSportWeekEditor.markUnavailable(once, date: "2026-10-02"), once)
    }

    func testAnUnplannedDayCanBeMarkedAndIsCreatedForIt() {
        let plan = MultiSportWeekEditor.markUnavailable(base, date: "2026-09-29")

        XCTAssertEqual(plan.day(on: "2026-09-29")?.isUnavailable, true)
        XCTAssertNil(plan.day(on: "2026-09-29")?.contentBeforeUnavailable)
        XCTAssertEqual(plan.days.map(\.date), ["2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
    }

    func testClearingUnavailableBringsTheSessionsBack() throws {
        let marked = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-02")

        let cleared = MultiSportWeekEditor.clearUnavailable(marked, date: "2026-10-02")

        let day = try XCTUnwrap(cleared.day(on: "2026-10-02"))
        let original = try XCTUnwrap(base.day(on: "2026-10-02"))
        XCTAssertFalse(day.isUnavailable)
        XCTAssertNil(day.contentBeforeUnavailable)
        XCTAssertEqual(day.content, original.content)
        XCTAssertEqual(day.focus, "Koppeltraining")
        XCTAssertTrue(day.isEdited)
        XCTAssertEqual(cleared.plannedMinutes, base.plannedMinutes)
    }

    func testClearingWithoutMemoryLeavesARestDay() throws {
        let marked = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-01")

        let day = try XCTUnwrap(MultiSportWeekEditor.clearUnavailable(marked, date: "2026-10-01").day(on: "2026-10-01"))

        XCTAssertFalse(day.isUnavailable)
        XCTAssertTrue(day.isRestDay)
        XCTAssertEqual(day.focus, "Ruhetag")
        XCTAssertTrue(day.isEdited)
    }

    func testClearingADayThatIsAvailableChangesNothing() {
        XCTAssertEqual(MultiSportWeekEditor.clearUnavailable(base, date: "2026-10-02"), base)
    }

    // MARK: - Ruhetag

    func testSetRestRemovesAllSessionsOfTheDay() throws {
        let day = try XCTUnwrap(MultiSportWeekEditor.setRest(base, date: "2026-10-02").day(on: "2026-10-02"))

        XCTAssertTrue(day.isRestDay)
        XCTAssertEqual(day.focus, "Ruhetag")
        XCTAssertTrue(day.isEdited)
        XCTAssertFalse(day.isUnavailable)
        XCTAssertNil(day.contentBeforeUnavailable)
    }

    func testSetRestOnARestDayOrAnUnavailableDayChangesNothing() {
        // Anders als in Plan v1 bleibt ein Ruhetag dabei unverändert (nicht als geändert markiert).
        XCTAssertEqual(MultiSportWeekEditor.setRest(base, date: "2026-10-01"), base)

        let marked = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-03")
        XCTAssertEqual(MultiSportWeekEditor.setRest(marked, date: "2026-10-03"), marked)
    }

    // MARK: - Tauschen und Verschieben

    func testSwapExchangesTheContentOfTwoDays() throws {
        let plan = MultiSportWeekEditor.swap(base, "2026-09-30", "2026-10-02")

        let first = try XCTUnwrap(plan.day(on: "2026-09-30"))
        let second = try XCTUnwrap(plan.day(on: "2026-10-02"))
        XCTAssertEqual(first.focus, "Koppeltraining")
        XCTAssertEqual(first.sessions, [Self.bikeSession(), Self.runSession()])
        XCTAssertEqual(second.focus, "Schwimmen Ausdauer")
        XCTAssertEqual(second.sessions, [Self.swimSession()])
        XCTAssertTrue(first.isEdited)
        XCTAssertTrue(second.isEdited)
        XCTAssertEqual(plan.plannedMinutes, base.plannedMinutes)
        // Die übrigen Tage bleiben.
        XCTAssertEqual(plan.day(on: "2026-10-03"), base.day(on: "2026-10-03"))
    }

    func testSwapWithAnUnplannedDayMovesTheSessionsThere() {
        let plan = MultiSportWeekEditor.swap(base, "2026-09-30", "2026-09-29")

        XCTAssertEqual(plan.days.first?.date, "2026-09-29")
        XCTAssertEqual(plan.day(on: "2026-09-29")?.sessions, [Self.swimSession()])
        XCTAssertEqual(plan.day(on: "2026-09-29")?.focus, "Schwimmen Ausdauer")
        XCTAssertEqual(plan.day(on: "2026-09-29")?.isEdited, true)
        XCTAssertEqual(plan.day(on: "2026-09-30")?.isRestDay, true)
        XCTAssertEqual(plan.day(on: "2026-09-30")?.focus, "Ruhetag")
        XCTAssertEqual(plan.day(on: "2026-09-30")?.isEdited, true)
    }

    func testSwapWithTheSameDayOrAnUnavailableDayChangesNothing() {
        XCTAssertEqual(MultiSportWeekEditor.swap(base, "2026-10-02", "2026-10-02"), base)

        let marked = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-04")
        XCTAssertEqual(MultiSportWeekEditor.swap(marked, "2026-10-02", "2026-10-04"), marked)
        XCTAssertEqual(MultiSportWeekEditor.swap(marked, "2026-10-04", "2026-10-02"), marked)
        // Dann entsteht auch kein neuer Tag.
        XCTAssertEqual(MultiSportWeekEditor.swap(marked, "2026-09-29", "2026-10-04"), marked)
    }

    func testMovingSessionsToARestDay() throws {
        let plan = MultiSportWeekEditor.moveToRestDay(base, from: "2026-10-03", to: "2026-10-04")

        let target = try XCTUnwrap(plan.day(on: "2026-10-04"))
        let source = try XCTUnwrap(plan.day(on: "2026-10-03"))
        XCTAssertEqual(target.sessions, [Self.thresholdTestSession()])
        XCTAssertEqual(target.focus, "Leistungstest")
        XCTAssertTrue(target.isEdited)
        XCTAssertTrue(source.isRestDay)
        XCTAssertEqual(source.focus, "Verschoben")
        XCTAssertTrue(source.isEdited)
        XCTAssertEqual(plan.plannedMinutes, base.plannedMinutes)
    }

    func testMovingADayWithTwoSessionsMovesBoth() {
        let plan = MultiSportWeekEditor.moveToRestDay(base, from: "2026-10-02", to: "2026-10-01")

        XCTAssertEqual(plan.day(on: "2026-10-01")?.sessions, [Self.bikeSession(), Self.runSession()])
        XCTAssertEqual(plan.day(on: "2026-10-01")?.focus, "Koppeltraining")
        XCTAssertEqual(plan.day(on: "2026-10-02")?.focus, "Verschoben")
        XCTAssertEqual(plan.day(on: "2026-10-02")?.isRestDay, true)
    }

    func testMovingOntoATrainingDayOrFromARestDayChangesNothing() {
        XCTAssertEqual(MultiSportWeekEditor.moveToRestDay(base, from: "2026-09-30", to: "2026-10-02"), base)
        XCTAssertEqual(MultiSportWeekEditor.moveToRestDay(base, from: "2026-10-01", to: "2026-10-04"), base)
        XCTAssertEqual(MultiSportWeekEditor.moveToRestDay(base, from: "2026-09-30", to: "2026-09-30"), base)
        // Ziel oder Ursprung ohne Eintrag: Es wird nichts angelegt.
        XCTAssertEqual(MultiSportWeekEditor.moveToRestDay(base, from: "2026-09-30", to: "2026-09-29"), base)
        XCTAssertEqual(MultiSportWeekEditor.moveToRestDay(base, from: "2026-09-29", to: "2026-10-01"), base)
    }

    func testMovingOntoARestDayWithoutTimeChangesNothing() {
        let marked = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-04")

        XCTAssertEqual(MultiSportWeekEditor.moveToRestDay(marked, from: "2026-09-30", to: "2026-10-04"), marked)
    }

    // MARK: - Umfang

    func testSetAmountResizesMinutesAndMetresProportionally() throws {
        let plan = MultiSportWeekEditor.setAmount(base, date: "2026-09-30", session: 0, amount: 3000)

        let session = try XCTUnwrap(plan.day(on: "2026-09-30")?.sessions.first)
        XCTAssertEqual(session.amount, 3000)
        XCTAssertEqual(session.minutes, 80)
        XCTAssertEqual(session.distanceMeters, 3000)
        XCTAssertEqual(session.unit, .meters)
        XCTAssertEqual(session.sport, SportID.swim)
        XCTAssertEqual(session.sessionType, .endurance)
        XCTAssertEqual(session.intensity, .moderate)
        XCTAssertEqual(session.focus, "Ausdauer")
        XCTAssertEqual(plan.day(on: "2026-09-30")?.focus, "Schwimmen Ausdauer")
        XCTAssertEqual(plan.day(on: "2026-09-30")?.isEdited, true)
    }

    func testSetAmountRoundsMinutesAndMetres() throws {
        // 1500 m in 40 min → 1000 m: 26,7 min → 27 min.
        let swimPlan = MultiSportWeekEditor.setAmount(base, date: "2026-09-30", session: 0, amount: 1000)
        let swim = try XCTUnwrap(swimPlan.day(on: "2026-09-30")?.sessions.first)
        XCTAssertEqual(swim.minutes, 27)
        XCTAssertEqual(swim.distanceMeters, 1000)

        // Rad 60 min mit 25 km → 90 min: 37,5 km. Das Laufen am selben Tag bleibt.
        let bikePlan = MultiSportWeekEditor.setAmount(base, date: "2026-10-02", session: 0, amount: 90)
        let day = try XCTUnwrap(bikePlan.day(on: "2026-10-02"))
        XCTAssertEqual(day.sessions.count, 2)
        XCTAssertEqual(day.sessions[0].amount, 90)
        XCTAssertEqual(day.sessions[0].minutes, 90)
        XCTAssertEqual(day.sessions[0].distanceMeters, 37_500)
        XCTAssertEqual(day.sessions[1], Self.runSession())
    }

    func testSetAmountIsClampedToTheManualRange() throws {
        let swimPlan = MultiSportWeekEditor.setAmount(base, date: "2026-09-30", session: 0, amount: 99_999)
        let swim = try XCTUnwrap(swimPlan.day(on: "2026-09-30")?.sessions.first)
        XCTAssertEqual(swim.amount, 6000)
        XCTAssertEqual(swim.minutes, 160)
        XCTAssertEqual(swim.distanceMeters, 6000)

        let bikePlan = MultiSportWeekEditor.setAmount(base, date: "2026-10-02", session: 0, amount: 1000)
        let bike = try XCTUnwrap(bikePlan.day(on: "2026-10-02")?.sessions.first)
        XCTAssertEqual(bike.amount, 360)
        XCTAssertEqual(bike.minutes, 360)
        XCTAssertEqual(bike.distanceMeters, 150_000)
    }

    func testZeroRemovesTheSessionAndAnEmptiedDayBecomesARestDay() throws {
        let day = try XCTUnwrap(MultiSportWeekEditor.setAmount(base, date: "2026-09-30", session: 0, amount: 0).day(on: "2026-09-30"))

        XCTAssertTrue(day.isRestDay)
        XCTAssertEqual(day.focus, "Ruhetag")
        XCTAssertTrue(day.isEdited)
        XCTAssertFalse(day.isUnavailable)

        // Weniger als 0 zählt als 0.
        let negative = try XCTUnwrap(MultiSportWeekEditor.setAmount(base, date: "2026-09-30", session: 0, amount: -50).day(on: "2026-09-30"))
        XCTAssertTrue(negative.isRestDay)
        XCTAssertEqual(negative.focus, "Ruhetag")
    }

    func testZeroOnADayWithTwoSessionsKeepsTheOtherOneAndTheFocus() throws {
        let day = try XCTUnwrap(MultiSportWeekEditor.setAmount(base, date: "2026-10-02", session: 0, amount: 0).day(on: "2026-10-02"))

        XCTAssertEqual(day.sessions, [Self.runSession()])
        XCTAssertEqual(day.focus, "Koppeltraining")
        XCTAssertTrue(day.isEdited)
    }

    func testSetAmountWithoutChangeOrForAMissingSessionChangesNothing() {
        XCTAssertEqual(MultiSportWeekEditor.setAmount(base, date: "2026-09-30", session: 0, amount: 1500), base)
        XCTAssertEqual(MultiSportWeekEditor.setAmount(base, date: "2026-09-30", session: 1, amount: 2000), base)
        XCTAssertEqual(MultiSportWeekEditor.setAmount(base, date: "2026-09-30", session: -1, amount: 2000), base)
        XCTAssertEqual(MultiSportWeekEditor.setAmount(base, date: "2026-10-01", session: 0, amount: 2000), base)

        let marked = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-02")
        XCTAssertEqual(MultiSportWeekEditor.setAmount(marked, date: "2026-10-02", session: 0, amount: 90), marked)
    }

    func testSetAmountWithoutPreviousAmountUsesTheTypicalSpeed() throws {
        let empty = Self.plan([
            Self.day("2026-09-30", "Neu", [
                WeekSession(sport: .swim, sessionType: .endurance, intensity: .easy, amount: 0, unit: .meters, minutes: 0, distanceMeters: 0, focus: ""),
                WeekSession(sport: .run, sessionType: .endurance, intensity: .easy, amount: 0, unit: .minutes, minutes: 0, distanceMeters: 0, focus: "")
            ]),
            Self.day("2026-10-01", "Neu", [
                WeekSession(sport: "kayak", sessionType: .endurance, intensity: .easy, amount: 0, unit: .minutes, minutes: 0, distanceMeters: 0, focus: "")
            ])
        ])

        // Schwimmen 0,8 m/s: 800 m ≈ 17 min.
        let swimPlan = MultiSportWeekEditor.setAmount(empty, date: "2026-09-30", session: 0, amount: 800)
        let swim = try XCTUnwrap(swimPlan.day(on: "2026-09-30")?.sessions.first)
        XCTAssertEqual(swim.amount, 800)
        XCTAssertEqual(swim.minutes, 17)
        XCTAssertEqual(swim.distanceMeters, 800)

        // Laufen 2,8 m/s: 30 min = 5040 m.
        let runPlan = MultiSportWeekEditor.setAmount(empty, date: "2026-09-30", session: 1, amount: 30)
        let runDay = try XCTUnwrap(runPlan.day(on: "2026-09-30"))
        XCTAssertEqual(runDay.sessions[1].amount, 30)
        XCTAssertEqual(runDay.sessions[1].minutes, 30)
        XCTAssertEqual(runDay.sessions[1].distanceMeters, 5040)

        // Unbekannte Sportart: mittleres Tempo 2 m/s.
        let kayakPlan = MultiSportWeekEditor.setAmount(empty, date: "2026-10-01", session: 0, amount: 30)
        let kayak = try XCTUnwrap(kayakPlan.day(on: "2026-10-01")?.sessions.first)
        XCTAssertEqual(kayak.minutes, 30)
        XCTAssertEqual(kayak.distanceMeters, 3600)

        // Die Registry entscheidet: Ohne Laufen-Modul gilt auch fürs Laufen das mittlere Tempo.
        let swimOnly = try SportRegistry(modules: [SwimModule()])
        let fallbackPlan = MultiSportWeekEditor.setAmount(empty, date: "2026-09-30", session: 1, amount: 30, registry: swimOnly)
        let fallback = try XCTUnwrap(fallbackPlan.day(on: "2026-09-30"))
        XCTAssertEqual(fallback.sessions[1].distanceMeters, 3600)
    }

    // MARK: - Einheit streichen und dazunehmen

    func testRemoveSessionKeepsTheOtherSession() throws {
        let day = try XCTUnwrap(MultiSportWeekEditor.removeSession(base, date: "2026-10-02", session: 1).day(on: "2026-10-02"))

        XCTAssertEqual(day.sessions, [Self.bikeSession()])
        XCTAssertEqual(day.focus, "Koppeltraining")
        XCTAssertTrue(day.isEdited)
    }

    func testRemovingTheOnlySessionMakesARestDay() throws {
        let day = try XCTUnwrap(MultiSportWeekEditor.removeSession(base, date: "2026-10-03", session: 0).day(on: "2026-10-03"))

        XCTAssertTrue(day.isRestDay)
        XCTAssertEqual(day.focus, "Ruhetag")
        XCTAssertTrue(day.isEdited)
    }

    func testRemovingAMissingSessionOrOnAnUnavailableDayChangesNothing() {
        XCTAssertEqual(MultiSportWeekEditor.removeSession(base, date: "2026-10-02", session: 2), base)
        XCTAssertEqual(MultiSportWeekEditor.removeSession(base, date: "2026-10-02", session: -1), base)
        XCTAssertEqual(MultiSportWeekEditor.removeSession(base, date: "2026-10-01", session: 0), base)

        let marked = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-02")
        XCTAssertEqual(MultiSportWeekEditor.removeSession(marked, date: "2026-10-02", session: 0), marked)
    }

    func testAddingASwimSessionOnARestDay() throws {
        let day = try XCTUnwrap(MultiSportWeekEditor.addSession(base, date: "2026-10-01", sport: .swim).day(on: "2026-10-01"))

        // 1000 m mit 0,8 m/s ≈ 21 min.
        let expected = WeekSession(
            sport: .swim, sessionType: .endurance, intensity: .easy, amount: 1000, unit: .meters,
            minutes: 21, distanceMeters: 1000, focus: "Locker"
        )
        XCTAssertEqual(day.sessions, [expected])
        XCTAssertEqual(day.focus, "Schwimmen locker")
        XCTAssertTrue(day.isEdited)
        XCTAssertFalse(expected.isHard)
    }

    func testAddingRunOrBikeTakesThirtyMinutes() throws {
        let runDay = try XCTUnwrap(MultiSportWeekEditor.addSession(base, date: "2026-10-04", sport: .run).day(on: "2026-10-04"))
        let expectedRun = WeekSession(
            sport: .run, sessionType: .endurance, intensity: .easy, amount: 30, unit: .minutes,
            minutes: 30, distanceMeters: 5040, focus: "Locker"
        )
        XCTAssertEqual(runDay.sessions, [expectedRun])
        XCTAssertEqual(runDay.focus, "Laufen locker")

        let bikeDay = try XCTUnwrap(MultiSportWeekEditor.addSession(base, date: "2026-10-04", sport: .bike).day(on: "2026-10-04"))
        let expectedBike = WeekSession(
            sport: .bike, sessionType: .endurance, intensity: .easy, amount: 30, unit: .minutes,
            minutes: 30, distanceMeters: 12_600, focus: "Locker"
        )
        XCTAssertEqual(bikeDay.sessions, [expectedBike])
        XCTAssertEqual(bikeDay.focus, "Radfahren locker")
    }

    func testASecondSessionKeepsTheFocusOfTheDay() throws {
        let day = try XCTUnwrap(MultiSportWeekEditor.addSession(base, date: "2026-09-30", sport: .run).day(on: "2026-09-30"))

        XCTAssertEqual(day.sessions.map(\.sport), [SportID.swim, SportID.run])
        XCTAssertEqual(day.sessions.first, Self.swimSession())
        XCTAssertEqual(day.focus, "Schwimmen Ausdauer")
        XCTAssertTrue(day.isEdited)
    }

    func testAtMostTwoSessionsPerDay() {
        XCTAssertEqual(MultiSportWeekEditor.addSession(base, date: "2026-10-02", sport: .swim), base)

        let once = MultiSportWeekEditor.addSession(base, date: "2026-10-01", sport: .swim)
        let twice = MultiSportWeekEditor.addSession(once, date: "2026-10-01", sport: .bike)
        XCTAssertEqual(twice.day(on: "2026-10-01")?.sessions.map(\.sport), [SportID.swim, SportID.bike])
        XCTAssertEqual(twice.day(on: "2026-10-01")?.focus, "Schwimmen locker")
        XCTAssertEqual(MultiSportWeekEditor.addSession(twice, date: "2026-10-01", sport: .run), twice)
    }

    func testAddingOnAnUnavailableDayOrForAnUnknownSportChangesNothing() {
        let marked = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-01")
        XCTAssertEqual(MultiSportWeekEditor.addSession(marked, date: "2026-10-01", sport: .swim), marked)

        XCTAssertEqual(MultiSportWeekEditor.addSession(base, date: "2026-10-01", sport: "kayak"), base)
        // Für eine unbekannte Sportart entsteht auch kein neuer Tag.
        XCTAssertEqual(MultiSportWeekEditor.addSession(base, date: "2026-09-29", sport: "kayak"), base)
    }

    func testAddingOnAnUnplannedDayCreatesIt() throws {
        let plan = MultiSportWeekEditor.addSession(base, date: "2026-09-29", sport: .run)

        XCTAssertEqual(plan.days.first?.date, "2026-09-29")
        let day = try XCTUnwrap(plan.day(on: "2026-09-29"))
        XCTAssertEqual(day.sessions.map(\.sport), [SportID.run])
        XCTAssertEqual(day.focus, "Laufen locker")
        XCTAssertTrue(day.isEdited)
    }

    func testAddSessionUsesTheGivenRegistry() throws {
        let registry = try SportRegistry(modules: [SwimModule(), RowingTestModule()])

        let day = try XCTUnwrap(MultiSportWeekEditor.addSession(base, date: "2026-10-01", sport: "rowing", registry: registry).day(on: "2026-10-01"))

        // Rudern plant nach Minuten mit 3,5 m/s.
        XCTAssertEqual(day.sessions.first?.unit, .minutes)
        XCTAssertEqual(day.sessions.first?.amount, 30)
        XCTAssertEqual(day.sessions.first?.distanceMeters, 6300)
        XCTAssertEqual(day.focus, "Rudern locker")
        // Eine Sportart, die die Standard-Registry nicht kennt, ändert nichts.
        XCTAssertEqual(MultiSportWeekEditor.addSession(base, date: "2026-10-01", sport: "kayak"), base)
    }

    // MARK: - Sportart tauschen

    func testChangeSportKeepsTheMinutesAndConvertsTheDistance() throws {
        // Laufen 20 min → Rad 20 min, Strecke mit 7 m/s.
        let day = try XCTUnwrap(MultiSportWeekEditor.changeSport(base, date: "2026-10-02", session: 1, to: .bike).day(on: "2026-10-02"))

        let expected = WeekSession(
            sport: .bike, sessionType: .endurance, intensity: .easy, amount: 20, unit: .minutes,
            minutes: 20, distanceMeters: 8400, focus: "Locker"
        )
        XCTAssertEqual(day.sessions[1], expected)
        XCTAssertEqual(day.sessions[0], Self.bikeSession())
        XCTAssertEqual(day.focus, "Koppeltraining")
        XCTAssertTrue(day.isEdited)
    }

    func testChangingToSwimmingConvertsMinutesToMetresRoundedToTheStep() throws {
        // Rad 60 min → 60 × 60 × 0,8 = 2880 m → 2900 m, das sind wieder 60 min.
        let plan = MultiSportWeekEditor.changeSport(base, date: "2026-10-02", session: 0, to: .swim)
        let session = try XCTUnwrap(plan.day(on: "2026-10-02")?.sessions.first)

        XCTAssertEqual(session.sport, SportID.swim)
        XCTAssertEqual(session.unit, .meters)
        XCTAssertEqual(session.amount, 2900)
        XCTAssertEqual(session.distanceMeters, 2900)
        XCTAssertEqual(session.minutes, 60)
        XCTAssertEqual(session.sessionType, .endurance)
        XCTAssertEqual(session.intensity, .easy)
        XCTAssertEqual(session.focus, "Grundlage")
    }

    func testChangingFromSwimmingKeepsTheMinutes() throws {
        // Schwimmen 1500 m in 40 min → Laufen 40 min, 40 × 60 × 2,8 = 6720 m.
        let plan = MultiSportWeekEditor.changeSport(base, date: "2026-09-30", session: 0, to: .run)
        let session = try XCTUnwrap(plan.day(on: "2026-09-30")?.sessions.first)

        XCTAssertEqual(session.sport, SportID.run)
        XCTAssertEqual(session.unit, .minutes)
        XCTAssertEqual(session.amount, 40)
        XCTAssertEqual(session.minutes, 40)
        XCTAssertEqual(session.distanceMeters, 6720)
        XCTAssertEqual(session.intensity, .moderate)
        XCTAssertNil(session.test)
    }

    func testChangeSportRoundsToTheStepOfTheNewSport() throws {
        let odd = Self.plan([Self.day("2026-09-30", "Kurz", [Self.runSession(33, meters: 5500), Self.runSession(1, meters: 170)])])

        // 33 min → 35 min.
        let roundedPlan = MultiSportWeekEditor.changeSport(odd, date: "2026-09-30", session: 0, to: .bike)
        let rounded = try XCTUnwrap(roundedPlan.day(on: "2026-09-30")?.sessions.first)
        XCTAssertEqual(rounded.amount, 35)
        XCTAssertEqual(rounded.minutes, 35)
        XCTAssertEqual(rounded.distanceMeters, 14_700)

        // Mindestens ein Schritt: 1 min → 5 min.
        let minimumPlan = MultiSportWeekEditor.changeSport(odd, date: "2026-09-30", session: 1, to: .bike)
        let minimum = try XCTUnwrap(minimumPlan.day(on: "2026-09-30"))
        XCTAssertEqual(minimum.sessions[1].amount, 5)
        XCTAssertEqual(minimum.sessions[1].minutes, 5)

        // Beim Schwimmen mindestens 100 m: 1 min × 60 × 0,8 = 48 m → 100 m ≈ 2 min.
        let swimPlan = MultiSportWeekEditor.changeSport(odd, date: "2026-09-30", session: 1, to: .swim)
        let swim = try XCTUnwrap(swimPlan.day(on: "2026-09-30"))
        XCTAssertEqual(swim.sessions[1].amount, 100)
        XCTAssertEqual(swim.sessions[1].distanceMeters, 100)
        XCTAssertEqual(swim.sessions[1].minutes, 2)
    }

    func testChangeSportWithoutMinutesUsesTheTypicalSpeedOfTheOldSport() throws {
        let noMinutes = Self.plan([
            Self.day("2026-09-30", "Technik", [
                WeekSession(sport: .swim, sessionType: .technique, intensity: .easy, amount: 1200, unit: .meters, minutes: 0, distanceMeters: 1200, focus: "Technik")
            ]),
            Self.day("2026-10-01", "Paddeln", [
                WeekSession(sport: "kayak", sessionType: .endurance, intensity: .easy, amount: 30, unit: .minutes, minutes: 0, distanceMeters: 0, focus: "Paddeln")
            ])
        ])

        // 1200 m mit 0,8 m/s = 25 min Rad.
        let bikePlan = MultiSportWeekEditor.changeSport(noMinutes, date: "2026-09-30", session: 0, to: .bike)
        let bike = try XCTUnwrap(bikePlan.day(on: "2026-09-30")?.sessions.first)
        XCTAssertEqual(bike.amount, 25)
        XCTAssertEqual(bike.minutes, 25)
        XCTAssertEqual(bike.distanceMeters, 10_500)
        XCTAssertEqual(bike.sessionType, .technique)
        XCTAssertEqual(bike.focus, "Technik")

        // Unbekannte alte Sportart in Minuten: die Minuten bleiben.
        let runPlan = MultiSportWeekEditor.changeSport(noMinutes, date: "2026-10-01", session: 0, to: .run)
        let changedRun = try XCTUnwrap(runPlan.day(on: "2026-10-01")?.sessions.first)
        XCTAssertEqual(changedRun.sport, SportID.run)
        XCTAssertEqual(changedRun.amount, 30)
        XCTAssertEqual(changedRun.minutes, 30)
        XCTAssertEqual(changedRun.distanceMeters, 5040)
    }

    func testATestBecomesAnEasyEnduranceSessionInTheNewSport() throws {
        XCTAssertTrue(Self.thresholdTestSession().isHard)

        let plan = MultiSportWeekEditor.changeSport(base, date: "2026-10-03", session: 0, to: .bike)
        let session = try XCTUnwrap(plan.day(on: "2026-10-03")?.sessions.first)

        let expected = WeekSession(
            sport: .bike, sessionType: .endurance, intensity: .easy, amount: 50, unit: .minutes,
            minutes: 50, distanceMeters: 21_000, focus: "Locker statt Leistungstest"
        )
        XCTAssertEqual(session, expected)
        XCTAssertNil(session.test)
        XCTAssertFalse(session.isHard)
        XCTAssertNil(session.target.testID)
        XCTAssertEqual(plan.day(on: "2026-10-03")?.isEdited, true)
    }

    func testChangeSportToTheSameOrAnUnknownSportChangesNothing() {
        XCTAssertEqual(MultiSportWeekEditor.changeSport(base, date: "2026-09-30", session: 0, to: .swim), base)
        XCTAssertEqual(MultiSportWeekEditor.changeSport(base, date: "2026-09-30", session: 0, to: "kayak"), base)
        XCTAssertEqual(MultiSportWeekEditor.changeSport(base, date: "2026-09-29", session: 0, to: "kayak"), base)
        XCTAssertEqual(MultiSportWeekEditor.changeSport(base, date: "2026-09-30", session: 1, to: .run), base)
        XCTAssertEqual(MultiSportWeekEditor.changeSport(base, date: "2026-10-01", session: 0, to: .run), base)

        let marked = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-02")
        XCTAssertEqual(MultiSportWeekEditor.changeSport(marked, date: "2026-10-02", session: 0, to: .run), marked)
    }

    // MARK: - Markierung "geändert"

    func testEveryChangeMarksOnlyTheChangedDays() {
        let changes: [(label: String, plan: WeekPlanV2, dates: [String])] = [
            ("keine Zeit", MultiSportWeekEditor.markUnavailable(base, date: "2026-10-02"), ["2026-10-02"]),
            ("Ruhetag", MultiSportWeekEditor.setRest(base, date: "2026-10-02"), ["2026-10-02"]),
            ("Umfang", MultiSportWeekEditor.setAmount(base, date: "2026-10-02", session: 0, amount: 90), ["2026-10-02"]),
            ("streichen", MultiSportWeekEditor.removeSession(base, date: "2026-10-02", session: 0), ["2026-10-02"]),
            ("Sportart", MultiSportWeekEditor.changeSport(base, date: "2026-10-02", session: 1, to: .swim), ["2026-10-02"]),
            ("dazu", MultiSportWeekEditor.addSession(base, date: "2026-10-01", sport: .swim), ["2026-10-01"]),
            ("tauschen", MultiSportWeekEditor.swap(base, "2026-10-01", "2026-10-02"), ["2026-10-01", "2026-10-02"]),
            ("verschieben", MultiSportWeekEditor.moveToRestDay(base, from: "2026-10-02", to: "2026-10-01"), ["2026-10-01", "2026-10-02"])
        ]
        for change in changes {
            let edited: [String] = change.plan.days.filter { (day: PlannedDay) -> Bool in day.isEdited }.map { (day: PlannedDay) -> String in day.date }
            XCTAssertEqual(edited, change.dates, change.label)
            XCTAssertNotEqual(change.plan, base, change.label)
        }
    }

    // MARK: - Neu geplant übernehmen

    func testMergeKeepsPastDaysAndReplacesFromTheStartDate() {
        let old = Self.plan([
            Self.day("2026-09-28", "Alt Mo", [Self.swimSession(1200, minutes: 30)]),
            Self.day("2026-09-29", "Alt Di", [Self.runSession(40, meters: 7000)], isEdited: true),
            Self.day("2026-09-30", "Alt Mi", [Self.swimSession()]),
            Self.restDay("2026-10-01")
        ])
        let new = Self.plan([
            Self.day("2026-09-30", "Neu Mi", [Self.bikeSession(45, meters: 18_000)]),
            Self.day("2026-10-01", "Neu Do", [Self.runSession(30, meters: 5000)])
        ])

        let merged = MultiSportWeekEditor.merge(existing: old, generated: new, fromDate: "2026-09-30")

        XCTAssertEqual(merged.days.map(\.date), ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"])
        XCTAssertEqual(merged.days.map(\.focus), ["Alt Mo", "Alt Di", "Neu Mi", "Neu Do"])
        // Vergangene Tage bleiben samt Markierung.
        XCTAssertEqual(merged.day(on: "2026-09-29")?.isEdited, true)
        XCTAssertEqual(merged.day(on: "2026-09-30")?.sessions.map(\.sport), [SportID.bike])
    }

    func testMergeReplacesEditedDaysFromTheStartDateOnLikeThePlanV1Editor() {
        // Wie WeekPlanEditor.merge: Ab dem Starttag gilt der neue Plan, auch für von Hand geänderte Tage.
        let edited = MultiSportWeekEditor.addSession(base, date: "2026-10-01", sport: .swim)
        let new = Self.plan([Self.day("2026-10-01", "Neu Do", [Self.runSession(30, meters: 5000)])])

        let merged = MultiSportWeekEditor.merge(existing: edited, generated: new, fromDate: "2026-09-30")

        XCTAssertEqual(merged.day(on: "2026-10-01")?.focus, "Neu Do")
        XCTAssertEqual(merged.day(on: "2026-10-01")?.isEdited, false)
        // Ohne Fenster gilt ab dem Starttag nur der neue Plan.
        XCTAssertEqual(merged.days.map(\.date), ["2026-10-01"])
    }

    func testMergeKeepsDaysWithoutTimeEvenIfTheServerPlannedThem() throws {
        let old = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-02")
        let new = Self.plan([
            Self.day("2026-09-30", "Neu", [Self.swimSession()]),
            Self.day("2026-10-02", "Neu", [Self.bikeSession(90, meters: 37_500)])
        ])

        let merged = MultiSportWeekEditor.merge(existing: old, generated: new, fromDate: "2026-09-30")

        let day = try XCTUnwrap(merged.day(on: "2026-10-02"))
        XCTAssertTrue(day.isUnavailable)
        XCTAssertTrue(day.isRestDay)
        XCTAssertEqual(day.focus, "Keine Zeit")
        XCTAssertEqual(day.contentBeforeUnavailable?.sessions, [Self.bikeSession(), Self.runSession()])
        XCTAssertEqual(merged.days.map(\.date), ["2026-09-30", "2026-10-02"])
    }

    func testMergeWithAWindowKeepsOldDaysBeyondItThatTheNewPlanDoesNotKnow() {
        let new = Self.plan([
            Self.day("2026-09-30", "Neu Mi", [Self.runSession()]),
            Self.day("2026-10-01", "Neu Do", [Self.swimSession()])
        ])

        // Das Fenster endet am 01.10.: 02. bis 04.10. stammen aus dem Plan davor.
        let merged = MultiSportWeekEditor.merge(existing: base, generated: new, fromDate: "2026-09-30", through: "2026-10-01")

        XCTAssertEqual(merged.days.map(\.date), ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
        XCTAssertEqual(merged.days.map(\.focus), ["Neu Mi", "Neu Do", "Koppeltraining", "Leistungstest", "Ruhetag"])
    }

    func testMergeWithAWindowTakesNewDaysBeyondItWithoutDuplicates() {
        // Der neue Plan kennt den 03.10. hinter dem Fenster: Dann gilt er, der alte Tag fällt weg.
        let new = Self.plan([
            Self.day("2026-09-30", "Neu Mi", [Self.runSession()]),
            Self.day("2026-10-03", "Neu Sa", [Self.bikeSession()])
        ])

        let merged = MultiSportWeekEditor.merge(existing: base, generated: new, fromDate: "2026-09-30", through: "2026-10-01")

        XCTAssertEqual(merged.days.map(\.date), ["2026-09-30", "2026-10-02", "2026-10-03", "2026-10-04"])
        XCTAssertEqual(merged.day(on: "2026-10-03")?.focus, "Neu Sa")
    }

    func testMergeWithAWindowKeepsADayWithoutTimeBeyondIt() {
        let old = MultiSportWeekEditor.markUnavailable(base, date: "2026-10-04")
        let new = Self.plan([Self.day("2026-09-30", "Neu", [Self.swimSession()])])

        let merged = MultiSportWeekEditor.merge(existing: old, generated: new, fromDate: "2026-09-30", through: "2026-09-30")

        XCTAssertEqual(merged.day(on: "2026-10-04")?.isUnavailable, true)
        XCTAssertEqual(merged.day(on: "2026-10-04")?.isEdited, true)
    }

    func testMergeWithoutAnExistingPlanOrAnotherWeekTakesTheNewOne() {
        let new = Self.plan([Self.day("2026-09-30", "Neu", [Self.swimSession()])])
        var other = base
        other.weekStart = "2026-09-21"

        XCTAssertEqual(MultiSportWeekEditor.merge(existing: nil, generated: new, fromDate: "2026-09-30"), new)
        XCTAssertEqual(MultiSportWeekEditor.merge(existing: other, generated: new, fromDate: "2026-09-30"), new)
    }

    func testMergeTakesRationaleAdjustmentsWishAndDateFromTheNewPlan() {
        let later = TestFixtures.now.addingTimeInterval(3600)
        let new = WeekPlanV2(
            weekStart: "2026-09-28", generatedAt: later, rationale: "Neu", adjustments: ["x"], wishes: "w",
            days: [Self.day("2026-09-30", "Neu", [Self.swimSession()])]
        )

        let merged = MultiSportWeekEditor.merge(existing: base, generated: new, fromDate: "2026-09-30")

        XCTAssertEqual(merged.weekStart, "2026-09-28")
        XCTAssertEqual(merged.generatedAt, later)
        XCTAssertEqual(merged.rationale, "Neu")
        XCTAssertEqual(merged.adjustments, ["x"])
        XCTAssertEqual(merged.wishes, "w")
    }

    func testMergeBehavesLikeThePlanV1Editor() {
        // Gleiche Tage, gleiche Markierungen: Plan v1 und Plan v2 übernehmen dieselben Tage.
        let dates = ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"]
        let oldV1 = WeekPlanEditor.markUnavailable(
            WeekFixtures.plan(days: dates.map { (date: String) -> WeekDayPlan in WeekFixtures.day(date) }),
            date: "2026-10-02"
        )
        let oldV2 = MultiSportWeekEditor.markUnavailable(
            Self.plan(dates.map { (date: String) -> PlannedDay in Self.day(date, "Alt", [Self.swimSession()]) }),
            date: "2026-10-02"
        )
        let newDates = ["2026-09-30", "2026-10-01", "2026-10-02"]
        let newV1 = WeekFixtures.plan(days: newDates.map { (date: String) -> WeekDayPlan in
            WeekFixtures.day(date, WeekFixtures.content(meters: 700))
        })
        let newV2 = Self.plan(newDates.map { (date: String) -> PlannedDay in Self.day(date, "Neu", [Self.swimSession(700, minutes: 20)]) })

        let windows: [String?] = [nil, "2026-10-02"]
        for through in windows {
            let label = through ?? "ohne Fenster"
            let mergedV1 = WeekPlanEditor.merge(existing: oldV1, generated: newV1, fromDate: "2026-09-30", through: through)
            let mergedV2 = MultiSportWeekEditor.merge(existing: oldV2, generated: newV2, fromDate: "2026-09-30", through: through)
            XCTAssertEqual(mergedV2.days.map(\.date), mergedV1.days.map(\.date), label)
            XCTAssertEqual(mergedV2.days.map(\.isUnavailable), mergedV1.days.map(\.isUnavailable), label)
            XCTAssertEqual(mergedV2.days.map(\.isEdited), mergedV1.days.map(\.isEdited), label)
        }

        let withoutWindow = MultiSportWeekEditor.merge(existing: oldV2, generated: newV2, fromDate: "2026-09-30")
        XCTAssertEqual(withoutWindow.days.map(\.date), ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02"])
        XCTAssertEqual(withoutWindow.day(on: "2026-10-02")?.isUnavailable, true)
        let withWindow = MultiSportWeekEditor.merge(existing: oldV2, generated: newV2, fromDate: "2026-09-30", through: "2026-10-02")
        XCTAssertEqual(withWindow.days.map(\.date), dates)
    }
}
