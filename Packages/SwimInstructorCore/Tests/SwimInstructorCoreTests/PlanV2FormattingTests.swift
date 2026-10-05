import XCTest
@testable import SwimInstructorCore

final class PlanV2FormattingTests: XCTestCase {
    // MARK: - Hilfen

    private static func targetStep(_ type: StepTarget?, _ value: Double?, rest: Int = 0) -> PlanStep {
        PlanStep(name: "Satz", repetitions: 1, measure: .duration, durationSeconds: 60, targetType: type, targetValue: value, restSeconds: rest)
    }

    private static func dayResponse(source: PlanSource, stale: Bool, reason: String?, date: String = "2026-09-30") -> DayPlanV2Response {
        DayPlanV2Response(
            source: source,
            date: date,
            generatedAt: TestFixtures.now,
            stale: stale,
            plan: DayPlanV2(rationale: "Ruhetag", sessions: []),
            fallbackReason: reason
        )
    }

    // MARK: - Umfang und Dauer

    func testAmountInTheUnitOfTheSport() {
        XCTAssertEqual(PlanV2Formatting.amount(1500, unit: .meters), "1.500 m")
        XCTAssertEqual(PlanV2Formatting.amount(400, unit: .meters), "400 m")
        // Ab 5 km in Kilometern.
        XCTAssertEqual(PlanV2Formatting.amount(10000, unit: .meters), "10,0 km")
        XCTAssertEqual(PlanV2Formatting.amount(12500, unit: .meters), "12,5 km")
        XCTAssertEqual(PlanV2Formatting.amount(58, unit: .minutes), "58 min")
        XCTAssertEqual(PlanV2Formatting.amount(135, unit: .minutes), "2:15 h")
    }

    func testDurationInMinutesSwitchesToHoursAtTwoHours() {
        XCTAssertEqual(PlanV2Formatting.duration(minutes: 0), "0 min")
        XCTAssertEqual(PlanV2Formatting.duration(minutes: 90), "90 min")
        XCTAssertEqual(PlanV2Formatting.duration(minutes: 119), "119 min")
        XCTAssertEqual(PlanV2Formatting.duration(minutes: 119.4), "119 min")
        // Gerundet wird vor dem Umschalten.
        XCTAssertEqual(PlanV2Formatting.duration(minutes: 119.5), "2:00 h")
        XCTAssertEqual(PlanV2Formatting.duration(minutes: 120), "2:00 h")
        XCTAssertEqual(PlanV2Formatting.duration(minutes: 135), "2:15 h")
        XCTAssertEqual(PlanV2Formatting.duration(minutes: 605), "10:05 h")
        // Nie negativ.
        XCTAssertEqual(PlanV2Formatting.duration(minutes: -5), "0 min")
    }

    func testDurationInSeconds() {
        XCTAssertEqual(PlanV2Formatting.duration(seconds: 0), "0 s")
        XCTAssertEqual(PlanV2Formatting.duration(seconds: 45), "45 s")
        XCTAssertEqual(PlanV2Formatting.duration(seconds: 59), "59 s")
        XCTAssertEqual(PlanV2Formatting.duration(seconds: 60), "1 min")
        XCTAssertEqual(PlanV2Formatting.duration(seconds: 90), "1:30 min")
        XCTAssertEqual(PlanV2Formatting.duration(seconds: 605), "10:05 min")
        XCTAssertEqual(PlanV2Formatting.duration(seconds: 1800), "30 min")
        XCTAssertEqual(PlanV2Formatting.duration(seconds: 3600), "60 min")
    }

    func testUnitSymbol() {
        XCTAssertEqual(PlanV2Formatting.unitSymbol(.meters), "m")
        XCTAssertEqual(PlanV2Formatting.unitSymbol(.minutes), "min")
    }

    func testSessionTitleNamesTheSportEvenWhenUnknown() {
        XCTAssertEqual(PlanV2Formatting.sessionTitle(sport: .swim, amount: 1500, unit: .meters), "Schwimmen · 1.500 m")
        XCTAssertEqual(PlanV2Formatting.sessionTitle(sport: .bike, amount: 58, unit: .minutes), "Radfahren · 58 min")
        XCTAssertEqual(PlanV2Formatting.sessionTitle(sport: .run, amount: 150, unit: .minutes), "Laufen · 2:30 h")
        XCTAssertEqual(PlanV2Formatting.sessionTitle(sport: "kayak", amount: 45, unit: .minutes), "kayak · 45 min")
        XCTAssertEqual(PlanV2Formatting.sessionTitle(sport: .swim, amount: 2000, unit: .meters, registry: .standard), "Schwimmen · 2.000 m")
    }

    // MARK: - Schritte

    func testStepVolumeByDistanceAndDuration() {
        XCTAssertEqual(PlanV2Formatting.stepVolume(PlanStep(name: "Technik", repetitions: 4, measure: .distance, distanceMeters: 50)), "4 × 50 m")
        XCTAssertEqual(PlanV2Formatting.stepVolume(PlanStep(name: "Einschwimmen", repetitions: 1, measure: .distance, distanceMeters: 1000)), "1.000 m")
        XCTAssertEqual(PlanV2Formatting.stepVolume(PlanStep(name: "Steigerung", repetitions: 3, measure: .duration, durationSeconds: 60)), "3 × 1 min")
        XCTAssertEqual(PlanV2Formatting.stepVolume(PlanStep(name: "Dauerlauf", repetitions: 1, measure: .duration, durationSeconds: 1800)), "30 min")
        XCTAssertEqual(PlanV2Formatting.stepVolume(PlanStep(name: "Kurz", repetitions: 6, measure: .duration, durationSeconds: 45)), "6 × 45 s")
    }

    func testStepVolumeFollowsTheMeasureWhenBothAreGiven() {
        XCTAssertEqual(
            PlanV2Formatting.stepVolume(PlanStep(name: "Satz", repetitions: 2, measure: .duration, distanceMeters: 400, durationSeconds: 90)),
            "2 × 1:30 min"
        )
        XCTAssertEqual(
            PlanV2Formatting.stepVolume(PlanStep(name: "Satz", repetitions: 2, measure: .distance, distanceMeters: 400, durationSeconds: 90)),
            "2 × 400 m"
        )
        // Unbekanntes Maß: Strecke vor Dauer.
        XCTAssertEqual(
            PlanV2Formatting.stepVolume(PlanStep(name: "Satz", repetitions: 1, measure: nil, distanceMeters: 400, durationSeconds: 90)),
            "400 m"
        )
    }

    func testStepVolumeFallsBackToWhateverIsThere() {
        // Dauer als Maß, aber nur eine Strecke.
        XCTAssertEqual(PlanV2Formatting.stepVolume(PlanStep(name: "Satz", repetitions: 1, measure: .duration, distanceMeters: 200)), "200 m")
        // Unbekanntes Maß mit Dauer.
        XCTAssertEqual(PlanV2Formatting.stepVolume(PlanStep(name: "Satz", repetitions: 1, measure: nil, durationSeconds: 45)), "45 s")
        // Weder Strecke noch Dauer.
        XCTAssertEqual(PlanV2Formatting.stepVolume(PlanStep(name: "Kraft", repetitions: 10, measure: .repetitions)), "10 ×")
        XCTAssertEqual(PlanV2Formatting.stepVolume(PlanStep(name: "Kraft", repetitions: 1, measure: .repetitions)), "")
    }

    func testTargetOfEveryKind() {
        XCTAssertEqual(PlanV2Formatting.target(Self.targetStep(.pacePerHundredMeters, 125)), "2:05 /100 m")
        XCTAssertEqual(PlanV2Formatting.target(Self.targetStep(.pacePerKilometer, 330)), "5:30 /km")
        XCTAssertEqual(PlanV2Formatting.target(Self.targetStep(.heartRateZone, 2)), "Zone 2")
        XCTAssertEqual(PlanV2Formatting.target(Self.targetStep(.power, 219.6)), "220 W")
        XCTAssertEqual(PlanV2Formatting.target(Self.targetStep(.speed, 28.4)), "28 km/h")
        XCTAssertEqual(PlanV2Formatting.target(Self.targetStep(.cadence, 90)), "90 /min")
        XCTAssertEqual(PlanV2Formatting.target(Self.targetStep(.strokeRate, 32)), "32 Züge/min")
        XCTAssertEqual(PlanV2Formatting.target(Self.targetStep(.perceivedEffort, 6)), "Anstrengung 6 von 10")

        for type in StepTarget.allCases {
            XCTAssertNotNil(PlanV2Formatting.target(Self.targetStep(type, 3)), type.rawValue)
        }
    }

    func testNoTargetWithoutTypeOrValue() {
        XCTAssertNil(PlanV2Formatting.target(Self.targetStep(nil, nil)))
        XCTAssertNil(PlanV2Formatting.target(Self.targetStep(.power, nil)))
        XCTAssertNil(PlanV2Formatting.target(Self.targetStep(nil, 200)))
    }

    func testStepDetailsJoinTargetAndRest() {
        XCTAssertEqual(PlanV2Formatting.stepDetails(Self.targetStep(.pacePerHundredMeters, 125, rest: 20)), "2:05 /100 m · 20 s Pause")
        XCTAssertEqual(PlanV2Formatting.stepDetails(Self.targetStep(.heartRateZone, 2)), "Zone 2")
        XCTAssertEqual(PlanV2Formatting.stepDetails(Self.targetStep(nil, nil, rest: 90)), "1:30 min Pause")
        XCTAssertEqual(PlanV2Formatting.stepDetails(Self.targetStep(nil, nil)), "")
    }

    // MARK: - Leistungswerte

    func testPerformanceValueInTheUnitOfTheContract() {
        XCTAssertEqual(PlanV2Formatting.performanceValue(105, unit: "s/100m"), "1:45 /100 m")
        XCTAssertEqual(PlanV2Formatting.performanceValue(290, unit: "s/km"), "4:50 /km")
        XCTAssertEqual(PlanV2Formatting.performanceValue(425, unit: "s"), "7:05 min")
        XCTAssertEqual(PlanV2Formatting.performanceValue(165, unit: "bpm"), "165 bpm")
        XCTAssertEqual(PlanV2Formatting.performanceValue(249.6, unit: "W"), "250 W")
    }

    func testTimeUnits() {
        XCTAssertTrue(PlanV2Formatting.isTimeUnit("s/100m"))
        XCTAssertTrue(PlanV2Formatting.isTimeUnit("s/km"))
        XCTAssertTrue(PlanV2Formatting.isTimeUnit("s"))
        XCTAssertFalse(PlanV2Formatting.isTimeUnit("bpm"))
        XCTAssertFalse(PlanV2Formatting.isTimeUnit("W"))
        XCTAssertFalse(PlanV2Formatting.isTimeUnit(""))
    }

    func testParseTimeReadsMinutesAndSecondsOrPlainSeconds() {
        XCTAssertEqual(PlanV2Formatting.parseTime("1:45"), 105)
        XCTAssertEqual(PlanV2Formatting.parseTime(" 1:45 "), 105)
        XCTAssertEqual(PlanV2Formatting.parseTime("0:59"), 59)
        XCTAssertEqual(PlanV2Formatting.parseTime("12:00"), 720)
        XCTAssertEqual(PlanV2Formatting.parseTime("105"), 105)
        XCTAssertEqual(PlanV2Formatting.parseTime("12.5"), 12.5)
    }

    func testParseTimeRejectsEverythingElse() {
        XCTAssertNil(PlanV2Formatting.parseTime(""))
        XCTAssertNil(PlanV2Formatting.parseTime("abc"))
        // Sekunden immer zweistellig und unter 60.
        XCTAssertNil(PlanV2Formatting.parseTime("1:5"))
        XCTAssertNil(PlanV2Formatting.parseTime("1:60"))
        XCTAssertNil(PlanV2Formatting.parseTime("1:-5"))
        XCTAssertNil(PlanV2Formatting.parseTime("-1:30"))
        XCTAssertNil(PlanV2Formatting.parseTime("1:"))
        XCTAssertNil(PlanV2Formatting.parseTime(":30"))
        XCTAssertNil(PlanV2Formatting.parseTime("1:4a"))
        XCTAssertNil(PlanV2Formatting.parseTime("1:02:03"))
    }

    func testOriginOfAPerformanceValue() {
        XCTAssertEqual(PlanV2Formatting.origin(.tested), "Test")
        XCTAssertEqual(PlanV2Formatting.origin(.manual), "von dir eingetragen")
        XCTAssertEqual(PlanV2Formatting.origin(.estimated), "geschätzt")
        XCTAssertEqual(PlanV2Formatting.origin(.formula), "Faustformel")
    }

    // MARK: - Herkunft des Tagesplans

    func testNoNoticeForAFreshPlan() {
        XCTAssertNil(PlanV2Formatting.sourceNotice(Self.dayResponse(source: .claude, stale: false, reason: nil)))
        XCTAssertNil(PlanV2Formatting.sourceNotice(Self.dayResponse(source: .cache, stale: false, reason: nil)))
    }

    func testNoticeForAnOldPlanFromTheContract() throws {
        let response = try PlanResponse.jsonDecoder().decode(
            DayPlanV2Response.self, from: RepoPaths.contractData("wire/plan-v2-today-fallback-response.json")
        )

        XCTAssertEqual(PlanV2Formatting.sourceNotice(response), "Letzter gültiger Plan vom 29.09.2026. Dein Coach war gerade nicht erreichbar.")
    }

    func testNoticeForAnEarlierPlanOfToday() {
        XCTAssertEqual(
            PlanV2Formatting.sourceNotice(Self.dayResponse(source: .fallback, stale: false, reason: "budget_exceeded")),
            "Früherer Plan von heute. Das Tageslimit für neue Pläne ist erreicht."
        )
        XCTAssertEqual(
            PlanV2Formatting.sourceNotice(Self.dayResponse(source: .fallback, stale: false, reason: nil)),
            "Früherer Plan von heute. Dein Coach hat keinen neuen Plan geliefert."
        )
        XCTAssertEqual(
            PlanV2Formatting.sourceNotice(Self.dayResponse(source: .fallback, stale: true, reason: "sanity_blocked", date: "2026-09-28")),
            "Letzter gültiger Plan vom 28.09.2026. Der neue Plan hat die Sicherheitsprüfung nicht bestanden."
        )
    }

    func testDayNoticeOnlyForAPlanFromAnotherDay() {
        let today = Self.dayResponse(source: .claude, stale: false, reason: nil, date: "2026-09-30")
        let yesterday = Self.dayResponse(source: .claude, stale: false, reason: nil, date: "2026-09-29")

        XCTAssertNil(PlanV2Formatting.dayNotice(today, now: TestFixtures.now, calendar: TestFixtures.utc))
        XCTAssertEqual(
            PlanV2Formatting.dayNotice(yesterday, now: TestFixtures.now, calendar: TestFixtures.utc),
            "Plan vom 29.09.2026. Öffne die iPhone-App für den Plan von heute."
        )
    }

}
