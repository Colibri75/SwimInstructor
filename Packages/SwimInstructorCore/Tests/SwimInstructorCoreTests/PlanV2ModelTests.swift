import XCTest
@testable import SwimInstructorCore

/// Plan v2: Dekodieren der Antworten aus `contracts/wire/plan-v2-*.json` und die abgeleiteten Werte der Modelle.
final class PlanV2ModelTests: XCTestCase {
    // MARK: - Hilfen

    /// `generated_at` der Vertragsdateien: 30.09.2026, 10:00 UTC.
    private static let contractGeneratedAt: Date = TestFixtures.now.addingTimeInterval(-2 * 3600)

    private static func contract<T: Decodable>(_ type: T.Type, _ file: String) throws -> T {
        try PlanResponse.jsonDecoder().decode(type, from: RepoPaths.contractData("wire/\(file)"))
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try PlanResponse.jsonDecoder().decode(type, from: Data(json.utf8))
    }

    private static func weekSession(
        _ sport: SportID,
        intensity: PlanIntensity = .easy,
        minutes: Double = 30,
        focus: String = "Grundlage",
        test: PlannedTest? = nil
    ) -> WeekSession {
        WeekSession(
            sport: sport,
            sessionType: test == nil ? .endurance : .test,
            intensity: intensity,
            amount: minutes,
            unit: .minutes,
            minutes: minutes,
            distanceMeters: 0,
            focus: focus,
            test: test
        )
    }

    private static func daySession(_ sport: SportID, minutes: Double, steps: [PlanStep]) -> DaySession {
        DaySession(
            sport: sport,
            sessionType: .endurance,
            intensity: .easy,
            focus: "",
            amount: minutes,
            unit: .minutes,
            distanceMeters: 0,
            durationMinutes: minutes,
            steps: steps
        )
    }

    private static func step(equipment: [String]) -> PlanStep {
        PlanStep(name: "Satz", repetitions: 1, measure: .distance, distanceMeters: 100, equipment: equipment)
    }

    private static let bikeTest = PlannedTest(
        id: "threshold_30min",
        displayName: "30-Minuten-Test",
        maximalEffort: true,
        produces: [.thresholdHeartRate, .thresholdPower]
    )

    private static func macroWeek(
        _ weekStart: String,
        totalMinutes: Double,
        swim: Double? = nil,
        run: Double? = nil,
        tests: [MacroTestSlot] = []
    ) -> MacroWeekV2 {
        var sports: [MacroSportVolume] = []
        if let swim {
            sports.append(MacroSportVolume(sport: .swim, unit: .meters, amount: swim, minutes: swim / 50, distanceMeters: swim, sessions: 2))
        }
        if let run {
            sports.append(MacroSportVolume(sport: .run, unit: .minutes, amount: run, minutes: run, distanceMeters: run * 170, sessions: 2))
        }
        return MacroWeekV2(
            weekStart: weekStart,
            phase: .base,
            deload: false,
            focus: "Aufbau",
            totalMinutes: totalMinutes,
            load: totalMinutes,
            sports: sports,
            tests: tests
        )
    }

    // MARK: - Tagesplan aus dem Vertrag

    func testTodayResponseDecodesSessionsStepsAndTest() throws {
        let response = try Self.contract(DayPlanV2Response.self, "plan-v2-today-response.json")

        XCTAssertEqual(response.planVersion, 2)
        XCTAssertEqual(response.source, .claude)
        XCTAssertEqual(response.date, "2026-09-30")
        XCTAssertEqual(response.generatedAt, Self.contractGeneratedAt)
        XCTAssertFalse(response.stale)
        XCTAssertEqual(response.adjustments, [])
        // Die Vorgabe der Anfrage setzt nur die App, der Server schickt sie nicht.
        XCTAssertNil(response.requestedTarget)
        XCTAssertNil(response.fallbackReason)
        XCTAssertEqual(response.wishes, "heute etwas Technik")
        XCTAssertTrue(response.plan.rationale.hasPrefix("Heute locker schwimmen"))
        XCTAssertEqual(response.plan.coachNotes, ["Vor dem Test gut essen und trinken."])
        XCTAssertEqual(response.plan.sessions.map(\.sport), [.swim, .bike])

        // Schwimmen: Technik nach Strecke.
        let swim = response.plan.sessions[0]
        XCTAssertEqual(swim.sessionType, .technique)
        XCTAssertEqual(swim.intensity, .easy)
        XCTAssertEqual(swim.focus, "Technik, lange Züge")
        XCTAssertNil(swim.test)
        XCTAssertEqual(swim.amount, 500)
        XCTAssertEqual(swim.unit, .meters)
        XCTAssertEqual(swim.distanceMeters, 500)
        XCTAssertEqual(swim.durationMinutes, 12)
        XCTAssertEqual(swim.steps.map(\.name), ["Einschwimmen", "Technik", "Ausschwimmen"])

        let technique = swim.steps[1]
        XCTAssertEqual(technique.repetitions, 4)
        XCTAssertEqual(technique.measure, .distance)
        XCTAssertEqual(technique.distanceMeters, 50)
        XCTAssertNil(technique.durationSeconds)
        XCTAssertEqual(technique.targetType, .pacePerHundredMeters)
        XCTAssertEqual(technique.targetValue, 125)
        XCTAssertEqual(technique.restSeconds, 20)
        XCTAssertEqual(technique.instructions, "Abschlag, auf lange Züge achten.")
        XCTAssertEqual(technique.cue, "Abschlag")
        XCTAssertEqual(technique.equipment, ["pull_buoy"])

        // Ohne Ziel: beide Felder leer.
        let cooldown = swim.steps[2]
        XCTAssertNil(cooldown.targetType)
        XCTAssertNil(cooldown.targetValue)
        XCTAssertEqual(cooldown.restSeconds, 0)

        // Rad: 30-Minuten-Test nach Dauer.
        let bike = response.plan.sessions[1]
        XCTAssertEqual(bike.sessionType, .test)
        XCTAssertEqual(bike.intensity, .hard)
        XCTAssertEqual(bike.focus, "30-Minuten-Test")
        XCTAssertEqual(bike.amount, 58)
        XCTAssertEqual(bike.unit, .minutes)
        XCTAssertEqual(bike.distanceMeters, 25250)
        XCTAssertEqual(bike.durationMinutes, 58)
        XCTAssertEqual(bike.test, Self.bikeTest)
        XCTAssertEqual(bike.steps.count, 4)
        XCTAssertTrue(bike.steps.allSatisfy { $0.measure == .duration })
        XCTAssertTrue(bike.steps.allSatisfy { $0.distanceMeters == nil })
        XCTAssertEqual(bike.steps.map(\.durationSeconds), [720, 60, 1800, 600])
        XCTAssertEqual(bike.steps.map(\.targetValue), [3, 6, 9, 2])
        XCTAssertTrue(bike.steps.allSatisfy { $0.targetType == .perceivedEffort })
        XCTAssertEqual(bike.steps[2].cue, "30 min hart, gleichmäßig")
    }

    func testTodayResponseTotalsEquipmentAndSessionsPerSport() throws {
        let response = try Self.contract(DayPlanV2Response.self, "plan-v2-today-response.json")
        let plan = response.plan

        XCTAssertFalse(plan.isRestDay)
        XCTAssertEqual(plan.totalMinutes, 70)
        XCTAssertEqual(plan.equipmentNeeded, ["pull_buoy"])
        XCTAssertEqual(plan.sessions(of: .swim).map(\.sessionType), [.technique])
        XCTAssertEqual(plan.sessions(of: .bike).map(\.sessionType), [.test])
        XCTAssertEqual(plan.sessions(of: .run), [])

        // Schwimmen: Die Schritte ergeben genau die geplante Strecke, ohne Dauer.
        let swim = plan.sessions[0]
        XCTAssertEqual(swim.steps.map(\.totalMeters), [200, 200, 100])
        XCTAssertEqual(swim.steps.reduce(0) { $0 + $1.totalMeters }, 500)
        XCTAssertEqual(swim.steps.reduce(0) { $0 + $1.totalSeconds }, 0)
        XCTAssertEqual(swim.equipmentNeeded, ["pull_buoy"])

        // Rad: 55 Minuten Belastung, dazu 3 × 60 s Pause ergeben die 58 Minuten der Einheit.
        let bike = plan.sessions[1]
        XCTAssertEqual(bike.steps.map(\.totalSeconds), [720, 180, 1800, 600])
        XCTAssertEqual(bike.steps.reduce(0) { $0 + $1.totalSeconds }, 3300)
        XCTAssertEqual(bike.steps.reduce(0) { $0 + $1.totalMeters }, 0)
        XCTAssertEqual(bike.equipmentNeeded, [])
    }

    func testFallbackResponseDecodes() throws {
        let response = try Self.contract(DayPlanV2Response.self, "plan-v2-today-fallback-response.json")

        XCTAssertEqual(response.planVersion, 2)
        XCTAssertEqual(response.source, .fallback)
        XCTAssertEqual(response.date, "2026-09-29")
        XCTAssertEqual(response.generatedAt, TestFixtures.now.addingTimeInterval(-30 * 3600))
        XCTAssertTrue(response.stale)
        XCTAssertEqual(response.fallbackReason, "timeout")
        XCTAssertNil(response.wishes)
        XCTAssertEqual(response.adjustments, [])
        XCTAssertEqual(response.plan.sessions.map(\.sport), [.swim, .bike])
        XCTAssertEqual(response.plan.totalMinutes, 70)
    }

    // MARK: - Schritte und Einheiten

    func testStepWithUnknownMeasureAndTargetStaysReadable() throws {
        let step = try Self.decodeJSON(PlanStep.self, """
        {
          "name": "Bahnen",
          "repetitions": 2,
          "measure": "laps",
          "distance_meters": 100,
          "duration_seconds": null,
          "target_type": "lactate",
          "target_value": 2.5,
          "rest_seconds": 15,
          "instructions": "neu",
          "cue": "Neu",
          "equipment": ["fins"]
        }
        """)

        // Unbekanntes Maß und Ziel fallen weg, der Rest bleibt.
        XCTAssertNil(step.measure)
        XCTAssertNil(step.targetType)
        XCTAssertEqual(step.targetValue, 2.5)
        XCTAssertEqual(step.name, "Bahnen")
        XCTAssertEqual(step.repetitions, 2)
        XCTAssertEqual(step.distanceMeters, 100)
        XCTAssertEqual(step.restSeconds, 15)
        XCTAssertEqual(step.equipment, ["fins"])
        XCTAssertEqual(step.totalMeters, 200)
    }

    func testStepWithoutOptionalFieldsGetsDefaults() throws {
        let step = try Self.decodeJSON(PlanStep.self, #"{"name": "Kraft", "repetitions": 10}"#)

        XCTAssertEqual(step, PlanStep(name: "Kraft", repetitions: 10, measure: nil))
        XCTAssertNil(step.measure)
        XCTAssertNil(step.distanceMeters)
        XCTAssertNil(step.durationSeconds)
        XCTAssertNil(step.targetType)
        XCTAssertNil(step.targetValue)
        XCTAssertEqual(step.restSeconds, 0)
        XCTAssertEqual(step.instructions, "")
        XCTAssertEqual(step.cue, "")
        XCTAssertEqual(step.equipment, [])
        // Ohne Strecke und Dauer sind beide Summen 0.
        XCTAssertEqual(step.totalMeters, 0)
        XCTAssertEqual(step.totalSeconds, 0)
    }

    func testStepWithoutNameOrRepetitionsIsRejected() {
        XCTAssertThrowsError(try Self.decodeJSON(PlanStep.self, #"{"repetitions": 1}"#))
        XCTAssertThrowsError(try Self.decodeJSON(PlanStep.self, #"{"name": "Satz"}"#))
    }

    func testStepTotalsMultiplyByRepetitions() {
        let distance = PlanStep(name: "200er", repetitions: 6, measure: .distance, distanceMeters: 200)
        let duration = PlanStep(name: "3 min", repetitions: 5, measure: .duration, durationSeconds: 180, restSeconds: 60)

        XCTAssertEqual(distance.totalMeters, 1200)
        XCTAssertEqual(distance.totalSeconds, 0)
        XCTAssertEqual(duration.totalMeters, 0)
        // Pausen zählen nicht mit.
        XCTAssertEqual(duration.totalSeconds, 900)
    }

    func testEquipmentIsCollectedWithoutDuplicatesInOrderOfUse() {
        let swim = Self.daySession(.swim, minutes: 40, steps: [
            Self.step(equipment: ["pull_buoy", "paddles"]),
            Self.step(equipment: []),
            Self.step(equipment: ["paddles", "fins"])
        ])
        let run = Self.daySession(.run, minutes: 30, steps: [Self.step(equipment: ["fins", "snorkel"])])
        let plan = DayPlanV2(rationale: "Zwei Einheiten", sessions: [swim, run])

        XCTAssertEqual(swim.equipmentNeeded, ["pull_buoy", "paddles", "fins"])
        XCTAssertEqual(plan.equipmentNeeded, ["pull_buoy", "paddles", "fins", "snorkel"])
        XCTAssertEqual(plan.totalMinutes, 70)
        XCTAssertEqual(plan.sessions(of: .run), [run])
        XCTAssertEqual(plan.coachNotes, [])
    }

    func testRestDayHasNoSessionsMinutesOrEquipment() {
        let plan = DayPlanV2(rationale: "Ruhetag", sessions: [], coachNotes: ["Schlafen"])

        XCTAssertTrue(plan.isRestDay)
        XCTAssertEqual(plan.totalMinutes, 0)
        XCTAssertEqual(plan.equipmentNeeded, [])
        XCTAssertEqual(plan.sessions(of: .swim), [])
        XCTAssertEqual(plan.coachNotes, ["Schlafen"])
    }

    func testDayResponseDefaults() {
        let response = DayPlanV2Response(
            source: .claude,
            date: "2026-09-30",
            generatedAt: TestFixtures.now,
            stale: false,
            plan: DayPlanV2(rationale: "Ruhetag", sessions: [])
        )

        XCTAssertEqual(response.planVersion, 2)
        XCTAssertEqual(response.adjustments, [])
        XCTAssertNil(response.fallbackReason)
        XCTAssertNil(response.wishes)
    }

    // MARK: - Sieben Tage

    func testWeekResponseDecodesSevenDays() throws {
        let response = try Self.contract(WeekPlanV2Response.self, "plan-v2-week-response.json")

        XCTAssertEqual(response.planVersion, 2)
        XCTAssertEqual(response.fromDate, "2026-09-30")
        XCTAssertEqual(response.generatedAt, Self.contractGeneratedAt)
        XCTAssertEqual(response.adjustments, [])
        XCTAssertEqual(response.wishes, "Freitag habe ich viel Zeit")
        XCTAssertTrue(response.plan.rationale.hasPrefix("Die Woche setzt den Gesamtplan"))
        XCTAssertEqual(response.plan.totalMinutes, 202)

        let days = response.plan.days
        XCTAssertEqual(days.map(\.date), ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06"])
        XCTAssertEqual(days.map(\.isRestDay), [true, false, false, false, false, true, false])
        XCTAssertEqual(days.map(\.totalMinutes), [0, 30, 58, 40, 50, 0, 24])
        // Markierungen des Athleten kommen nie vom Server.
        XCTAssertEqual(days.map(\.isUnavailable), [false, false, false, false, false, false, false])
        XCTAssertEqual(days.map(\.isEdited), [false, false, false, false, false, false, false])
        XCTAssertTrue(days.allSatisfy { $0.contentBeforeUnavailable == nil })
        XCTAssertEqual(days[0].focus, "Ruhetag")

        let testDay = days[2]
        XCTAssertEqual(testDay.focus, "Leistungstest Rad")
        let bike = try XCTUnwrap(testDay.sessions.first)
        XCTAssertEqual(bike.sport, .bike)
        XCTAssertEqual(bike.sessionType, .test)
        XCTAssertEqual(bike.intensity, .hard)
        XCTAssertEqual(bike.amount, 58)
        XCTAssertEqual(bike.unit, .minutes)
        XCTAssertEqual(bike.minutes, 58)
        XCTAssertEqual(bike.distanceMeters, 25250)
        XCTAssertEqual(bike.focus, "30-Minuten-Test")
        XCTAssertEqual(bike.test, Self.bikeTest)
        XCTAssertTrue(bike.isHard)
        XCTAssertEqual(bike.target.testID, "threshold_30min")

        XCTAssertEqual(days[3].sessions.map(\.sport), [.run, .swim])
        XCTAssertEqual(days[3].sessions.map(\.unit), [.minutes, .meters])
        XCTAssertEqual(days[1].sessions.first?.isHard, false)
        XCTAssertNil(days[1].sessions.first?.test)
        XCTAssertEqual(days[6].sessions.first?.isHard, true)
        XCTAssertEqual(days[6].sessions.first?.sessionType, .intervals)

        // Als Woche gehalten: Die Tage ergeben den Wochenumfang der Antwort.
        let week = WeekPlanV2(
            weekStart: "2026-09-28",
            generatedAt: response.generatedAt,
            rationale: response.plan.rationale,
            adjustments: response.adjustments,
            wishes: response.wishes,
            days: days
        )
        XCTAssertEqual(week.plannedMinutes, response.plan.totalMinutes)
        XCTAssertEqual(week.sports, [.swim, .bike, .run])
    }

    func testWeekSessionIsHardWithHardIntensityOrAMaximalTest() {
        let easyTest = PlannedTest(id: "entry_easy_25min", displayName: "Einstiegstest locker", maximalEffort: false, produces: [.thresholdHeartRate])

        XCTAssertTrue(Self.weekSession(.run, intensity: .hard).isHard)
        XCTAssertTrue(Self.weekSession(.bike, intensity: .easy, test: Self.bikeTest).isHard)
        XCTAssertFalse(Self.weekSession(.run, intensity: .moderate, test: easyTest).isHard)
        XCTAssertFalse(Self.weekSession(.swim, intensity: .easy).isHard)
        XCTAssertFalse(Self.weekSession(.swim, intensity: .moderate).isHard)
    }

    func testWeekSessionTargetCarriesTheTestAndCutsTheFocus() {
        let longFocus = String(repeating: "a", count: 130)
        let session = Self.weekSession(.bike, intensity: .hard, minutes: 58, focus: longFocus, test: Self.bikeTest)

        let target = session.target

        XCTAssertEqual(target.sport, .bike)
        XCTAssertEqual(target.sessionType, .test)
        XCTAssertEqual(target.intensity, .hard)
        XCTAssertEqual(target.amount, 58)
        XCTAssertEqual(target.testID, "threshold_30min")
        XCTAssertEqual(target.focus, String(repeating: "a", count: 120))

        // Kurzer Schwerpunkt bleibt, ohne Test keine Kennung.
        let plain = Self.weekSession(.swim, focus: "Technik").target
        XCTAssertEqual(plain.focus, "Technik")
        XCTAssertNil(plain.testID)
    }

    func testPlannedDayContentCanBeReadAndReplaced() {
        let content = PlannedDayContent(focus: "Rad", sessions: [Self.weekSession(.bike, minutes: 60)])
        var day = PlannedDay(date: "2026-10-01", content: content, isEdited: true)

        XCTAssertEqual(day.id, "2026-10-01")
        XCTAssertEqual(day.content, content)
        XCTAssertEqual(day.focus, "Rad")
        XCTAssertEqual(day.totalMinutes, 60)
        XCTAssertFalse(day.isRestDay)

        day.content = PlannedDayContent(focus: "Lauf und Schwimmen", sessions: [Self.weekSession(.run, minutes: 40), Self.weekSession(.swim, minutes: 20)])

        XCTAssertEqual(day.focus, "Lauf und Schwimmen")
        XCTAssertEqual(day.sessions.map(\.sport), [.run, .swim])
        XCTAssertEqual(day.totalMinutes, 60)
        // Datum und Markierungen bleiben.
        XCTAssertEqual(day.date, "2026-10-01")
        XCTAssertTrue(day.isEdited)
        XCTAssertFalse(day.isUnavailable)

        day.content = .rest()
        XCTAssertTrue(day.isRestDay)
        XCTAssertEqual(day.focus, "Ruhetag")
    }

    func testRestContent() {
        XCTAssertEqual(PlannedDayContent.rest(), PlannedDayContent(focus: "Ruhetag", sessions: []))
        XCTAssertEqual(PlannedDayContent.rest(focus: "Keine Zeit").focus, "Keine Zeit")
        XCTAssertTrue(PlannedDayContent.rest().isRestDay)
        XCTAssertFalse(PlannedDayContent(focus: "Lauf", sessions: [Self.weekSession(.run)]).isRestDay)
    }

    func testPlannedDayTargetIsARestDayWhenUnavailable() {
        var day = PlannedDay(date: "2026-10-01", content: PlannedDayContent(focus: "Schwimmen", sessions: [Self.weekSession(.swim, focus: "Technik")]))

        XCTAssertEqual(day.target, DayTargetV2(focus: "Schwimmen", sessions: [Self.weekSession(.swim, focus: "Technik").target]))

        day.isUnavailable = true

        XCTAssertEqual(day.target, DayTargetV2(focus: "Schwimmen", sessions: []))
    }

    func testPlannedDayTargetFocusIsNilWhenEmptyAndCutWhenLong() {
        let empty = PlannedDay(date: "2026-10-01", content: PlannedDayContent(focus: "", sessions: []))
        let long = PlannedDay(date: "2026-10-01", content: PlannedDayContent(focus: String(repeating: "b", count: 200), sessions: []))

        XCTAssertNil(empty.target.focus)
        XCTAssertEqual(empty.target.sessions, [])
        XCTAssertEqual(long.target.focus, String(repeating: "b", count: 120))
    }

    func testPlannedDayDecoderFillsTheAthleteFields() throws {
        let day = try Self.decodeJSON(PlannedDay.self, #"{"date": "2026-10-01", "sessions": []}"#)

        XCTAssertEqual(day.date, "2026-10-01")
        XCTAssertEqual(day.focus, "")
        XCTAssertEqual(day.sessions, [])
        XCTAssertFalse(day.isUnavailable)
        XCTAssertNil(day.contentBeforeUnavailable)
        XCTAssertFalse(day.isEdited)

        // Ohne Datum oder Einheiten ist der Tag unbrauchbar.
        XCTAssertThrowsError(try Self.decodeJSON(PlannedDay.self, #"{"date": "2026-10-01", "focus": "Lauf"}"#))
        XCTAssertThrowsError(try Self.decodeJSON(PlannedDay.self, #"{"focus": "Lauf", "sessions": []}"#))
    }

    func testPlannedDayRoundTripKeepsTheAthleteChanges() throws {
        let before = PlannedDayContent(focus: "Rad", sessions: [Self.weekSession(.bike, intensity: .hard, minutes: 58, test: Self.bikeTest)])
        let day = PlannedDay(
            date: "2026-10-02",
            content: .rest(focus: "Keine Zeit"),
            isUnavailable: true,
            contentBeforeUnavailable: before,
            isEdited: true
        )

        let data = try PlanResponse.jsonEncoder().encode(day)
        let decoded = try PlanResponse.jsonDecoder().decode(PlannedDay.self, from: data)

        XCTAssertEqual(decoded, day)
        XCTAssertEqual(decoded.contentBeforeUnavailable?.sessions.first?.test?.id, "threshold_30min")
    }

    func testWeekPlanSortsDaysAndCountsOnlyDaysWithTime() {
        let monday = PlannedDay(date: "2026-10-05", content: PlannedDayContent(focus: "Rad", sessions: [Self.weekSession(.bike, minutes: 60)]))
        let sunday = PlannedDay(date: "2026-10-04", content: PlannedDayContent(focus: "Lauf", sessions: [Self.weekSession(.run, minutes: 40)]))
        let blocked = PlannedDay(
            date: "2026-10-03",
            content: PlannedDayContent(focus: "Schwimmen", sessions: [Self.weekSession(.swim, minutes: 30)]),
            isUnavailable: true
        )

        let week = WeekPlanV2(weekStart: "2026-09-28", generatedAt: TestFixtures.now, rationale: "Woche", days: [monday, sunday, blocked])

        XCTAssertEqual(week.id, "2026-09-28")
        XCTAssertEqual(week.days.map(\.date), ["2026-10-03", "2026-10-04", "2026-10-05"])
        XCTAssertEqual(week.adjustments, [])
        XCTAssertNil(week.wishes)
        // Der Tag ohne Zeit zählt nicht mit.
        XCTAssertEqual(week.plannedMinutes, 100)
        XCTAssertEqual(week.day(on: "2026-10-04")?.focus, "Lauf")
        XCTAssertNil(week.day(on: "2026-10-06"))
    }

    func testWeekPlanSportsInOrderOfFirstAppearance() {
        let days = [
            PlannedDay(date: "2026-10-01", content: PlannedDayContent(focus: "Lauf", sessions: [Self.weekSession(.run)])),
            PlannedDay(date: "2026-09-30", content: .rest()),
            PlannedDay(date: "2026-10-02", content: PlannedDayContent(focus: "Rad und Lauf", sessions: [Self.weekSession(.bike), Self.weekSession(.run)])),
            PlannedDay(date: "2026-10-03", content: PlannedDayContent(focus: "Schwimmen", sessions: [Self.weekSession(.swim)]))
        ]

        let week = WeekPlanV2(weekStart: "2026-09-28", generatedAt: TestFixtures.now, rationale: "Woche", days: days)

        XCTAssertEqual(week.sports, [.run, .bike, .swim])
        XCTAssertEqual(WeekPlanV2(weekStart: "2026-09-28", generatedAt: TestFixtures.now, rationale: "leer", days: []).sports, [])
    }

    // MARK: - Gesamtplan

    func testMacroResponseDecodes() throws {
        let response = try Self.contract(MacroPlanV2Response.self, "plan-v2-macro-response.json")

        XCTAssertEqual(response.planVersion, 2)
        XCTAssertEqual(response.goalDay, "2026-11-08")
        XCTAssertEqual(response.generatedAt, Self.contractGeneratedAt)
        XCTAssertEqual(response.adjustments, [])
        XCTAssertNil(response.changes)
        XCTAssertNil(response.feedback)
        XCTAssertTrue(response.plan.rationale.hasPrefix("Sechs Wochen bis zum Ziel"))

        let weeks = response.plan.weeks
        XCTAssertEqual(weeks.map(\.weekStart), ["2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26", "2026-11-02"])
        XCTAssertEqual(weeks.map(\.phase), [.specific, .specific, .specific, .specific, .taper, .goalWeek])
        XCTAssertEqual(weeks.map(\.deload), [false, false, true, false, false, false])
        XCTAssertEqual(weeks.map(\.totalMinutes), [210, 227, 155, 246, 143, 121])
        XCTAssertEqual(weeks.map(\.load), [190, 205, 140, 222, 129, 109])
        XCTAssertEqual(weeks[2].focus, "Entlastung")

        let first = weeks[0]
        XCTAssertEqual(first.id, "2026-09-28")
        XCTAssertEqual(first.sports.map(\.sport), [.swim, .bike, .run])
        XCTAssertEqual(first.volume(of: .bike), MacroSportVolume(sport: .bike, unit: .minutes, amount: 100, minutes: 100, distanceMeters: 45900, sessions: 2))
        XCTAssertEqual(first.volume(of: .swim)?.unit, .meters)
        XCTAssertNil(first.volume(of: "kayak"))
        XCTAssertEqual(first.tests, [MacroTestSlot(sport: .bike, testID: "threshold_30min", displayName: "30-Minuten-Test")])
        XCTAssertEqual(weeks[1].tests, [MacroTestSlot(sport: .run, testID: "entry_easy_25min", displayName: "Einstiegstest locker")])
        XCTAssertEqual(weeks[5].volume(of: .run)?.sessions, 1)
    }

    func testMacroPlanFromTheContractAnswersPeaksTestsAndUpcomingWeeks() throws {
        let plan = try Self.contract(MacroPlanV2Response.self, "plan-v2-macro-response.json").macroPlan(goalKey: "ziel")

        XCTAssertEqual(plan.sports, [.swim, .bike, .run])
        XCTAssertEqual(plan.peakAmount(of: .swim), 3800)
        XCTAssertEqual(plan.peakAmount(of: .bike), 120)
        XCTAssertEqual(plan.peakAmount(of: .run), 50)
        XCTAssertEqual(plan.peakAmount(of: "kayak"), 0)
        XCTAssertEqual(plan.peakMinutes, 246)

        let slots = plan.testSlots
        XCTAssertEqual(slots.map { slot in slot.weekStart }, ["2026-09-28", "2026-10-05"])
        XCTAssertEqual(slots.map { slot in slot.test.testID }, ["threshold_30min", "entry_easy_25min"])
        XCTAssertEqual(slots.map { slot in slot.test.sport }, [.bike, .run])

        XCTAssertEqual(plan.weeks(from: "2026-10-19").map(\.weekStart), ["2026-10-19", "2026-10-26", "2026-11-02"])
        // Ein Tag mitten in der Woche: nur die Wochen, die danach beginnen.
        XCTAssertEqual(plan.weeks(from: "2026-10-28").map(\.weekStart), ["2026-11-02"])
        XCTAssertEqual(plan.weeks(from: "2026-12-01"), [])
        XCTAssertEqual(plan.week(starting: "2026-10-12")?.deload, true)
        XCTAssertNil(plan.week(starting: "2026-10-13"))
    }

    func testReviseResponseDecodesChangesAndFeedback() throws {
        let response = try Self.contract(MacroPlanV2Response.self, "plan-v2-revise-response.json")

        XCTAssertEqual(response.planVersion, 2)
        XCTAssertEqual(response.goalDay, "2026-11-08")
        XCTAssertEqual(response.changes, ["Laufen in den ersten zwei Wochen 5 Minuten mehr", "Schwimmen dort um 300 m weniger"])
        XCTAssertEqual(response.feedback, "Mehr Laufen bitte, dafür weniger Schwimmen.")
        XCTAssertEqual(response.adjustments.count, 2)
        XCTAssertTrue(response.adjustments[0].hasPrefix("Woche ab 12.10.: Schwimmen von 2500 m auf 2300 m"))
        XCTAssertEqual(response.plan.weeks.count, 6)
        XCTAssertEqual(response.plan.weeks.first?.volume(of: .swim)?.amount, 3200)
        XCTAssertEqual(response.plan.weeks.first?.volume(of: .run)?.amount, 45)

        let plan = response.macroPlan(goalKey: "ziel")
        XCTAssertEqual(plan.peakAmount(of: .swim), 3600)
        XCTAssertEqual(plan.peakMinutes, 242)
    }

    func testMacroResponseBecomesTheStoredPlanWithItsRounds() throws {
        let response = try Self.contract(MacroPlanV2Response.self, "plan-v2-revise-response.json")
        let round = MacroFeedbackRound(
            feedback: "Mehr Laufen bitte, dafür weniger Schwimmen.",
            changes: response.changes ?? [],
            adjustments: response.adjustments,
            revisedAt: TestFixtures.now
        )

        let plan = response.macroPlan(goalKey: "ziel", feedbackRounds: [round])

        XCTAssertEqual(plan.goalKey, "ziel")
        XCTAssertEqual(plan.goalDay, "2026-11-08")
        XCTAssertEqual(plan.generatedAt, Self.contractGeneratedAt)
        XCTAssertEqual(plan.rationale, response.plan.rationale)
        XCTAssertEqual(plan.adjustments, response.adjustments)
        XCTAssertEqual(plan.weeks, response.plan.weeks)
        XCTAssertEqual(plan.feedbackRounds, [round])
        // Ohne Runden beginnt ein neuer Plan ohne.
        XCTAssertEqual(response.macroPlan(goalKey: "ziel").feedbackRounds, [])
    }

    func testMacroWeekDecoderFillsMissingFields() throws {
        let week = try Self.decodeJSON(MacroWeekV2.self, """
        {
          "week_start": "2026-10-05",
          "phase": "base",
          "deload": true,
          "sports": [
            {"sport": "run", "unit": "minutes", "amount": 60, "minutes": 60, "distance_meters": 10000, "sessions": 3}
          ]
        }
        """)

        XCTAssertEqual(week, MacroWeekV2(
            weekStart: "2026-10-05",
            phase: .base,
            deload: true,
            focus: "",
            totalMinutes: 0,
            load: 0,
            sports: [MacroSportVolume(sport: .run, unit: .minutes, amount: 60, minutes: 60, distanceMeters: 10000, sessions: 3)],
            tests: []
        ))

        // Ohne Wochenbeginn, Phase, Entlastung oder Sportarten ist die Woche unbrauchbar.
        XCTAssertThrowsError(try Self.decodeJSON(MacroWeekV2.self, #"{"phase": "base", "deload": false, "sports": []}"#))
        XCTAssertThrowsError(try Self.decodeJSON(MacroWeekV2.self, #"{"week_start": "2026-10-05", "deload": false, "sports": []}"#))
        XCTAssertThrowsError(try Self.decodeJSON(MacroWeekV2.self, #"{"week_start": "2026-10-05", "phase": "base", "sports": []}"#))
        XCTAssertThrowsError(try Self.decodeJSON(MacroWeekV2.self, #"{"week_start": "2026-10-05", "phase": "base", "deload": false}"#))
    }

    func testMacroPlanSortsWeeksAndDecodesWithoutRounds() throws {
        let plan = try Self.decodeJSON(MacroPlanV2.self, """
        {
          "goal_key": "ziel",
          "goal_day": "2026-11-08",
          "generated_at": "2026-09-30T10:00:00Z",
          "rationale": "Plan",
          "weeks": [
            {"week_start": "2026-10-12", "phase": "taper", "deload": false, "sports": []},
            {"week_start": "2026-10-05", "phase": "base", "deload": false, "sports": []}
          ]
        }
        """)

        XCTAssertEqual(plan.goalKey, "ziel")
        XCTAssertEqual(plan.generatedAt, Self.contractGeneratedAt)
        XCTAssertEqual(plan.weeks.map(\.weekStart), ["2026-10-05", "2026-10-12"])
        XCTAssertEqual(plan.adjustments, [])
        XCTAssertEqual(plan.feedbackRounds, [])

        // Auch der Initialisierer sortiert.
        let built = MacroPlanV2(
            goalKey: "ziel",
            goalDay: "2026-11-08",
            generatedAt: TestFixtures.now,
            rationale: "Plan",
            weeks: [Self.macroWeek("2026-10-19", totalMinutes: 100), Self.macroWeek("2026-10-05", totalMinutes: 90)]
        )
        XCTAssertEqual(built.weeks.map(\.weekStart), ["2026-10-05", "2026-10-19"])
        XCTAssertEqual(built.adjustments, [])
        XCTAssertEqual(built.feedbackRounds, [])
    }

    func testMacroPlanHelpersWithMixedSports() {
        let plan = MacroPlanV2(
            goalKey: "ziel",
            goalDay: "2026-11-08",
            generatedAt: TestFixtures.now,
            rationale: "Plan",
            weeks: [
                Self.macroWeek("2026-10-12", totalMinutes: 200, swim: 2000, run: 90, tests: [MacroTestSlot(sport: .run, testID: "threshold_30min", displayName: "30-Minuten-Test")]),
                Self.macroWeek("2026-10-05", totalMinutes: 150, run: 120),
                Self.macroWeek("2026-10-19", totalMinutes: 180, swim: 2500, tests: [MacroTestSlot(sport: .swim, testID: "css_400_200", displayName: "CSS-Test 400/200 m")])
            ]
        )

        // Laufen kommt in der ersten Woche zuerst vor.
        XCTAssertEqual(plan.sports, [.run, .swim])
        XCTAssertEqual(plan.peakAmount(of: .swim), 2500)
        XCTAssertEqual(plan.peakAmount(of: .run), 120)
        XCTAssertEqual(plan.peakAmount(of: .bike), 0)
        XCTAssertEqual(plan.peakMinutes, 200)
        XCTAssertEqual(plan.testSlots.map { slot in slot.weekStart }, ["2026-10-12", "2026-10-19"])
        XCTAssertEqual(plan.testSlots.map { slot in slot.test.testID }, ["threshold_30min", "css_400_200"])
    }

    func testEmptyMacroPlanHasNoPeaksOrTests() {
        let plan = MacroPlanV2(goalKey: "ziel", goalDay: "2026-11-08", generatedAt: TestFixtures.now, rationale: "leer", weeks: [])

        XCTAssertEqual(plan.sports, [])
        XCTAssertEqual(plan.peakAmount(of: .swim), 0)
        XCTAssertEqual(plan.peakMinutes, 0)
        XCTAssertTrue(plan.testSlots.isEmpty)
        XCTAssertEqual(plan.weeks(from: "2026-01-01"), [])
    }

    // MARK: - Schlüssel des Ziels

    private static func goal(targetDate: Date) -> TrainingGoal {
        TrainingGoal(
            template: "triathlon_olympic",
            disciplines: [
                TrainingGoal.Discipline(sport: .swim, distanceMeters: 1500, targetDurationSeconds: 1800),
                TrainingGoal.Discipline(sport: .bike, distanceMeters: 40000),
                TrainingGoal.Discipline(sport: .run, distanceMeters: 10000, targetDurationSeconds: 2999.9)
            ],
            targetDate: targetDate,
            trainingDaysPerWeek: 5,
            weeklyHours: 7.5,
            emphasis: [
                TrainingGoal.Emphasis(sport: .swim, percent: 30),
                TrainingGoal.Emphasis(sport: .bike, percent: 40),
                TrainingGoal.Emphasis(sport: .run, percent: 30)
            ]
        )
    }

    func testPlanKeyNamesEverythingThatShapesThePlan() throws {
        let targetDate = try XCTUnwrap(TestFixtures.utc.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12)))
        let goal = Self.goal(targetDate: targetDate)
        let key = goal.planKey(calendar: TestFixtures.utc)

        XCTAssertEqual(key, "race|swim:1500:1800,bike:40000:-,run:10000:2999|2026-11-08|swim:30,bike:40,run:30")

        // Die Vorlage gehört nicht dazu.
        var withoutTemplate = goal
        withoutTemplate.template = nil
        XCTAssertEqual(withoutTemplate.planKey(calendar: TestFixtures.utc), key)

        // Trainingstage und Stunden auch nicht: Sie kommen aus dem Wochenraster und gelten ohne neuen Gesamtplan.
        var otherDays = goal
        otherDays.trainingDaysPerWeek = 6
        var otherHours = goal
        otherHours.weeklyHours = 8
        XCTAssertEqual(otherDays.planKey(calendar: TestFixtures.utc), key)
        XCTAssertEqual(otherHours.planKey(calendar: TestFixtures.utc), key)

        // Jede Planungsgröße ändert den Schlüssel.
        var otherDistance = goal
        otherDistance.disciplines[2].distanceMeters = 21100
        var otherTime = goal
        otherTime.disciplines[0].targetDurationSeconds = nil
        var otherKind = goal
        otherKind.kind = .time
        var otherEmphasis = goal
        otherEmphasis.emphasis = [
            TrainingGoal.Emphasis(sport: .swim, percent: 20),
            TrainingGoal.Emphasis(sport: .bike, percent: 50),
            TrainingGoal.Emphasis(sport: .run, percent: 30)
        ]
        let otherDay = Self.goal(targetDate: targetDate.addingTimeInterval(7 * 86_400))
        let changed: [TrainingGoal] = [otherDistance, otherTime, otherKind, otherEmphasis, otherDay]
        for other in changed {
            XCTAssertNotEqual(other.planKey(calendar: TestFixtures.utc), key)
        }
        XCTAssertEqual(otherTime.planKey(calendar: TestFixtures.utc), "race|swim:1500:-,bike:40000:-,run:10000:2999|2026-11-08|swim:30,bike:40,run:30")
    }

    func testPlanKeyUsesTheCalendarForTheTargetDay() throws {
        // 23:30 UTC ist in Berlin schon der nächste Tag.
        let targetDate = try XCTUnwrap(TestFixtures.utc.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 30)))
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let goal = Self.goal(targetDate: targetDate)

        XCTAssertTrue(goal.planKey(calendar: TestFixtures.utc).contains("|2026-11-08|"))
        XCTAssertTrue(goal.planKey(calendar: berlin).contains("|2026-11-09|"))
    }
}
