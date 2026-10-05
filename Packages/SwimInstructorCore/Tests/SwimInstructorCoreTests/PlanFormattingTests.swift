import XCTest
@testable import SwimInstructorCore

final class PlanFormattingTests: XCTestCase {
    func testPace() {
        XCTAssertEqual(PlanFormatting.pace(140), "2:20")
        XCTAssertEqual(PlanFormatting.pace(94.7), "1:35")
        XCTAssertEqual(PlanFormatting.pace(65), "1:05")
    }

    func testDistanceSwitchesToKilometersAboveFive() {
        XCTAssertEqual(PlanFormatting.distance(1600), "1.600 m")
        XCTAssertEqual(PlanFormatting.distance(4999.6), "5.000 m")
        XCTAssertEqual(PlanFormatting.distance(5000), "5,0 km")
        XCTAssertEqual(PlanFormatting.distance(42195), "42,2 km")
    }

    func testMetersAndRest() {
        XCTAssertEqual(PlanFormatting.meters(400), "400 m")
        XCTAssertEqual(PlanFormatting.meters(1600), "1.600 m")
        XCTAssertEqual(PlanFormatting.rest(30), "30 s")
        XCTAssertEqual(PlanFormatting.rest(90), "1:30 min")
    }

    func testLabelsCoverAllCases() {
        for type in SessionType.allCases {
            XCTAssertFalse(PlanFormatting.sessionType(type).isEmpty)
        }
        for intensity in PlanIntensity.allCases {
            XCTAssertFalse(PlanFormatting.intensity(intensity).isEmpty)
        }
        XCTAssertEqual(PlanFormatting.sessionType(.rest), "Ruhetag")
    }

    func testIsoDay() {
        XCTAssertEqual(PlanFormatting.isoDay(TestFixtures.now, calendar: TestFixtures.utc), "2026-09-30")
        XCTAssertEqual(PlanFormatting.germanDate("2026-09-30"), "30.09.2026")
        XCTAssertEqual(PlanFormatting.germanDate("unbekannt"), "unbekannt")
    }

    // MARK: - Watch

    func testElapsed() {
        XCTAssertEqual(PlanFormatting.elapsed(0), "0:00")
        XCTAssertEqual(PlanFormatting.elapsed(754), "12:34")
        XCTAssertEqual(PlanFormatting.elapsed(3723), "1:02:03")
        XCTAssertEqual(PlanFormatting.elapsed(-5), "0:00")
    }

    func testEquipmentNamesAreGermanAndUnknownOnesStayReadable() {
        XCTAssertEqual(PlanFormatting.equipmentName("pull_buoy"), "Pull Buoy")
        XCTAssertEqual(PlanFormatting.equipmentName("paddles"), "Paddles")
        XCTAssertEqual(PlanFormatting.equipmentName("fins"), "Flossen")
        XCTAssertEqual(PlanFormatting.equipmentName("snorkel"), "Schnorchel")
        XCTAssertEqual(PlanFormatting.equipmentName("kickboard"), "Kickboard")
        XCTAssertEqual(PlanFormatting.equipmentName("ankle_band"), "Beinband")
        XCTAssertEqual(PlanFormatting.equipmentName("hand_weights"), "Hand Weights")
    }

    func testEquipmentListIsCommaSeparatedAndEmptyWithoutItems() {
        XCTAssertEqual(PlanFormatting.equipment(["pull_buoy", "paddles"]), "Pull Buoy, Paddles")
        XCTAssertEqual(PlanFormatting.equipment([]), "")
    }

    func testStateTextCoversEveryState() {
        let states: [WeekDayState] = [.unplanned, .upcoming, .today, .followed, .shorter, .longer, .missed, .restKept, .restBroken, .skipped]

        XCTAssertEqual(Set(states.map { PlanFormatting.stateText($0) }).count, states.count)
        XCTAssertEqual(PlanFormatting.stateText(.missed), "nicht geschwommen")
        XCTAssertEqual(PlanFormatting.stateText(.skipped), "keine Zeit")
    }

    func testMacroPhaseNamesAreGerman() {
        XCTAssertEqual(PlanFormatting.macroPhase(.base), "Aufbau")
        XCTAssertEqual(PlanFormatting.macroPhase(.specific), "Zielspezifisch")
        XCTAssertEqual(PlanFormatting.macroPhase(.taper), "Zuspitzen")
        XCTAssertEqual(PlanFormatting.macroPhase(.goalWeek), "Zielwoche")
        XCTAssertEqual(PlanFormatting.macroPhase(.maintain), "Erhalten")
    }
}

