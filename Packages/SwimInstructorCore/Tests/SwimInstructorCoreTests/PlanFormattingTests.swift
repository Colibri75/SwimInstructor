import XCTest
@testable import SwimInstructorCore

final class PlanFormattingTests: XCTestCase {
    func testPace() {
        XCTAssertEqual(PlanFormatting.pace(140), "2:20")
        XCTAssertEqual(PlanFormatting.pace(94.7), "1:35")
        XCTAssertEqual(PlanFormatting.pace(65), "1:05")
    }

    func testMetersAndRest() {
        XCTAssertEqual(PlanFormatting.meters(400), "400 m")
        XCTAssertEqual(PlanFormatting.meters(1600), "1.600 m")
        XCTAssertEqual(PlanFormatting.rest(30), "30 s")
        XCTAssertEqual(PlanFormatting.rest(90), "1:30 min")
    }

    func testSetLines() {
        let main = PlanSet(name: "Hauptsatz", repetitions: 6, distanceMeters: 200, targetPaceSecondsPerHundredMeters: 140, restSeconds: 30, instructions: "")
        let warmUp = PlanSet(name: "Einschwimmen", repetitions: 1, distanceMeters: 400, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: "")

        XCTAssertEqual(PlanFormatting.setVolume(main), "6 × 200 m")
        XCTAssertEqual(PlanFormatting.setDetails(main), "2:20 /100 m · 30 s Pause")
        XCTAssertEqual(PlanFormatting.setVolume(warmUp), "400 m")
        XCTAssertEqual(PlanFormatting.setDetails(warmUp), "")
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

    func testSourceNotice() {
        XCTAssertNil(PlanFormatting.sourceNotice(TestFixtures.response(source: .claude)))
        XCTAssertNil(PlanFormatting.sourceNotice(TestFixtures.response(source: .cache)))
        XCTAssertEqual(
            PlanFormatting.sourceNotice(TestFixtures.response(date: "2026-09-29", source: .fallback, stale: true)),
            "Letzter gültiger Plan vom 29.09.2026. Claude war gerade nicht erreichbar."
        )
        XCTAssertEqual(
            PlanFormatting.sourceNotice(TestFixtures.response(source: .fallback, stale: false)),
            "Früherer Plan von heute. Claude war gerade nicht erreichbar."
        )
    }

    func testIsoDay() {
        XCTAssertEqual(PlanFormatting.isoDay(TestFixtures.now, calendar: TestFixtures.utc), "2026-09-30")
        XCTAssertEqual(PlanFormatting.germanDate("2026-09-30"), "30.09.2026")
        XCTAssertEqual(PlanFormatting.germanDate("unbekannt"), "unbekannt")
    }

    // MARK: - Watch

    func testDayNoticeOnlyForOtherDays() {
        XCTAssertNil(PlanFormatting.dayNotice(TestFixtures.response(date: "2026-09-30"), now: TestFixtures.now, calendar: TestFixtures.utc))
        XCTAssertEqual(
            PlanFormatting.dayNotice(TestFixtures.response(date: "2026-09-29"), now: TestFixtures.now, calendar: TestFixtures.utc),
            "Plan vom 29.09.2026. Öffne die iPhone-App für den Plan von heute."
        )
    }

    func testElapsed() {
        XCTAssertEqual(PlanFormatting.elapsed(0), "0:00")
        XCTAssertEqual(PlanFormatting.elapsed(754), "12:34")
        XCTAssertEqual(PlanFormatting.elapsed(3723), "1:02:03")
        XCTAssertEqual(PlanFormatting.elapsed(-5), "0:00")
    }

    func testRepetitionAndRemaining() {
        let set = PlanSet(name: "Hauptsatz", repetitions: 6, distanceMeters: 200, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: "")
        let position = PlanPosition(setIndex: 1, set: set, repetition: 3, metersIntoRepetition: 50)
        let single = PlanPosition(
            setIndex: 0,
            set: PlanSet(name: "Einschwimmen", repetitions: 1, distanceMeters: 1200, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: ""),
            repetition: 1,
            metersIntoRepetition: 0
        )

        XCTAssertEqual(PlanFormatting.repetition(position), "3 von 6 × 200 m")
        XCTAssertEqual(PlanFormatting.remaining(position), "noch 150 m")
        XCTAssertEqual(PlanFormatting.repetition(single), "1.200 m")
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

    func testDaySummary() {
        let session = WeekDayPlan(date: "2026-10-02", content: WeekDayContent(sessionType: .technique, intensity: .easy, targetDistanceMeters: 1000, estimatedDurationMinutes: 35, focus: "Technik"))

        XCTAssertEqual(PlanFormatting.daySummary(session), "Technik, 1.000 m")
        XCTAssertEqual(PlanFormatting.daySummary(WeekDayPlan(date: "2026-10-01", content: .rest())), "Ruhetag")
        XCTAssertEqual(PlanFormatting.daySummary(WeekPlanEditor.markUnavailable(WeekPlan(weekStart: "2026-09-28", generatedAt: Date(), rationale: "", days: [session]), date: "2026-10-02").day(on: "2026-10-02")), "keine Zeit")
        XCTAssertEqual(PlanFormatting.daySummary(nil), "nicht geplant")
    }
}

