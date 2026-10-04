import XCTest
@testable import SwimInstructorCore

/// Texte, die Plan-Tab, Verlauf und Testergebnis der App ohne Sportart im Wortlaut zeigen.
final class PlanV2DisplayTextTests: XCTestCase {
    private let swim: SportID = "swim"
    private let run: SportID = "run"

    private func session(_ sport: SportID, amount: Double, unit: PlanUnit) -> WeekSession {
        WeekSession(sport: sport, sessionType: .endurance, intensity: .easy, amount: amount, unit: unit, minutes: 40, distanceMeters: 0, focus: "")
    }

    func testStateTextNamesNoSport() {
        XCTAssertEqual(PlanV2Formatting.stateText(.missed), "nicht trainiert")
        XCTAssertEqual(PlanV2Formatting.stateText(.restBroken), "trotz Ruhetag trainiert")
        // Alles andere wie in Plan v1.
        XCTAssertEqual(PlanV2Formatting.stateText(.followed), PlanFormatting.stateText(.followed))
        XCTAssertEqual(PlanV2Formatting.stateText(.skipped), "keine Zeit")
    }

    func testOutcomeTextCoversEveryOutcome() {
        let expected: [(AdherenceOutcome, String)] = [
            (.followed, "umgesetzt"), (.shorter, "kürzer"), (.longer, "länger"), (.missed, "nicht trainiert"),
            (.restKept, "Ruhetag eingehalten"), (.restBroken, "trotz Ruhetag trainiert"), (.pending, "offen")
        ]
        for (outcome, text) in expected {
            XCTAssertEqual(PlanV2Formatting.outcomeText(outcome), text)
        }
    }

    func testComparisonShowsPlanOnlyWhenThereIsOne() {
        XCTAssertEqual(PlanV2Formatting.comparison(planned: 1500, actual: 1200, unit: .meters), "1.200 m von 1.500 m")
        XCTAssertEqual(PlanV2Formatting.comparison(planned: 60, actual: 45, unit: .minutes), "45 min von 60 min")
        XCTAssertEqual(PlanV2Formatting.comparison(planned: 0, actual: 35, unit: .minutes), "35 min")
    }

    func testDaySummaryListsEverySession() {
        XCTAssertEqual(PlanV2Formatting.daySummary(nil), "nicht geplant")
        let rest = PlannedDay(date: "2026-10-05", content: .rest())
        XCTAssertEqual(PlanV2Formatting.daySummary(rest), "Ruhetag")
        let busy = PlannedDay(
            date: "2026-10-06",
            content: PlannedDayContent(focus: "", sessions: [session(swim, amount: 2000, unit: .meters), session(run, amount: 40, unit: .minutes)])
        )
        XCTAssertEqual(PlanV2Formatting.daySummary(busy), "Schwimmen · 2.000 m, Laufen · 40 min")
        // "Keine Zeit" geht vor dem, was vorher geplant war.
        let unavailable = PlannedDay(date: "2026-10-07", content: busy.content, isUnavailable: true)
        XCTAssertEqual(PlanV2Formatting.daySummary(unavailable), "keine Zeit")
    }

    func testMacroVolumeCountsSessions() {
        let one = MacroSportVolume(sport: run, unit: .minutes, amount: 45, minutes: 45, distanceMeters: 0, sessions: 1)
        XCTAssertEqual(PlanV2Formatting.macroVolume(one), "Laufen 45 min in 1 Einheit")
        let three = MacroSportVolume(sport: swim, unit: .meters, amount: 6000, minutes: 150, distanceMeters: 6000, sessions: 3)
        XCTAssertEqual(PlanV2Formatting.macroVolume(three), "Schwimmen 6,0 km in 3 Einheiten")
    }

    func testParseTimeRejectsNegativeAndNonFiniteNumbers() {
        XCTAssertNil(PlanV2Formatting.parseTime("-5"))
        XCTAssertNil(PlanV2Formatting.parseTime("nan"))
        XCTAssertNil(PlanV2Formatting.parseTime("inf"))
        XCTAssertEqual(PlanV2Formatting.parseTime("0"), 0)
    }

    func testChangePercentHasASign() {
        XCTAssertEqual(PlanV2Formatting.changePercent(4.4), "+4 %")
        XCTAssertEqual(PlanV2Formatting.changePercent(-12.3), "−12 %")
        XCTAssertEqual(PlanV2Formatting.changePercent(0.2), "±0 %")
    }
}
