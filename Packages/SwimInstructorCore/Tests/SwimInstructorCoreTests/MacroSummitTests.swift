import XCTest
@testable import SwimInstructorCore

/// Der Gesamtplan als Berg und die Farben der Sportarten.
final class MacroSummitTests: XCTestCase {
    private func week(_ start: String, _ minutes: Double, _ phase: MacroPhase = .base) -> MacroWeekV2 {
        MacroWeekV2(weekStart: start, phase: phase, deload: false, focus: "", totalMinutes: minutes, load: 0, sports: [])
    }

    func testTheHeightIsTheTrainingSoFarAndTheGoalIsTheSummit() {
        let plan = MacroPlanV2(goalKey: "ziel", goalDay: "2026-10-25", generatedAt: TestFixtures.now, rationale: "r", weeks: [
            week("2026-10-05", 300), week("2026-10-12", 100), week("2026-10-19", 400, .taper), week("2026-09-28", 200)
        ])

        let profile = MacroSummitProfile(plan: plan, currentWeekStart: "2026-10-05")

        XCTAssertEqual(profile.points.map(\.x), [0, 0.25, 0.5, 0.75, 1])
        // Wochen nach Datum: 200, 300, 100 (flach), 400 von 1000 Minuten.
        XCTAssertEqual(profile.points.map(\.y), [0, 0.2, 0.5, 0.6, 1])
        XCTAssertEqual(profile.currentIndex, 1)
        XCTAssertEqual(profile.segments.map(\.phase), [.base, .base, .base, .taper])
        XCTAssertEqual(profile.segments.last?.fromX, 0.75)
    }

    func testWithoutMinutesTheWayRisesEvenlyAndAWeekOutsideHasNoMarker() {
        let plan = MacroPlanV2(goalKey: "ziel", goalDay: "2026-10-18", generatedAt: TestFixtures.now, rationale: "r", weeks: [
            week("2026-10-05", 0), week("2026-10-12", 0)
        ])

        let profile = MacroSummitProfile(plan: plan, currentWeekStart: "2026-11-02")

        XCTAssertEqual(profile.points.map(\.y), [0, 0.5, 1])
        XCTAssertNil(profile.currentIndex)
        XCTAssertEqual(MacroSummitProfile(plan: MacroPlanV2(goalKey: "z", goalDay: "2026-10-18", generatedAt: TestFixtures.now, rationale: "r", weeks: []), currentWeekStart: "2026-10-05").points.count, 1)
    }

    func testEverySportHasItsOwnColorAndUnknownSportsAreNeutral() {
        let registry = SportRegistry.standard
        let colors = registry.modules.map(\.colorRGB)

        XCTAssertEqual(Set(colors).count, colors.count)
        XCTAssertFalse(colors.contains(SportRegistry.neutralColorRGB))
        XCTAssertEqual(registry.colorRGB(for: SportID(rawValue: "kayak")), SportRegistry.neutralColorRGB)
    }
}
