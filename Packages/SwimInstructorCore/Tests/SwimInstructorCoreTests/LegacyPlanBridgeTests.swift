import XCTest
@testable import SwimInstructorCore

final class LegacyPlanBridgeTests: XCTestCase {
    // Plan v1 mit Pace, Hilfsmitteln, Kurztext, Hinweisen, Korrekturen und Wunsch.
    private func legacyResponse() -> PlanResponse {
        PlanResponse(
            source: .fallback,
            date: "2026-09-29",
            generatedAt: TestFixtures.now,
            stale: true,
            plan: TrainingPlan(
                sessionType: .threshold,
                intensity: .hard,
                rationale: "Schwelle halten.",
                totalDistanceMeters: 1600,
                estimatedDurationMinutes: 45,
                sets: [
                    PlanSet(
                        name: "Einschwimmen", repetitions: 1, distanceMeters: 400,
                        targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: "locker"
                    ),
                    PlanSet(
                        name: "Hauptsatz", repetitions: 6, distanceMeters: 200,
                        targetPaceSecondsPerHundredMeters: 105, restSeconds: 30, instructions: "gleichmäßig",
                        equipment: ["pull_buoy"], cue: "Zug lang"
                    )
                ],
                coachNotes: ["Auf lockere Atmung achten."]
            ),
            adjustments: ["Umfang gekürzt"],
            fallbackReason: "timeout",
            wishes: "kurz"
        )
    }

    private func legacyRestDay() -> PlanResponse {
        PlanResponse(
            source: .claude,
            date: "2026-10-01",
            generatedAt: TestFixtures.now,
            stale: false,
            plan: TrainingPlan(
                sessionType: .rest, intensity: .rest, rationale: "Erholung nach dem harten Tag.",
                totalDistanceMeters: 0, estimatedDurationMinutes: 0, sets: [], coachNotes: ["Früh schlafen."]
            ),
            adjustments: [],
            wishes: "frei"
        )
    }

    /// Eine Einheit nach Minuten, wie Rad und Laufen sie planen.
    private func minutesSession(_ sport: SportID, _ minutes: Double) -> DaySession {
        DaySession(
            sport: sport, sessionType: .endurance, intensity: .easy, focus: "Grundlage",
            amount: minutes, unit: .minutes, distanceMeters: 0, durationMinutes: minutes, steps: []
        )
    }

    private func response(_ sessions: [DaySession], rationale: String = "Zwei Einheiten.", notes: [String] = ["Viel trinken."]) -> DayPlanV2Response {
        DayPlanV2Response(
            source: .cache,
            date: "2026-10-02",
            generatedAt: TestFixtures.now,
            stale: false,
            plan: DayPlanV2(rationale: rationale, sessions: sessions, coachNotes: notes),
            adjustments: ["Rad gekürzt"],
            fallbackReason: nil,
            wishes: "Koppeltraining"
        )
    }

    // MARK: - Plan v1 als Plan v2

    func testLegacyPlanBecomesOneSwimSessionWithPlanVersionOne() throws {
        let converted = DayPlanV2Response(legacy: legacyResponse())

        XCTAssertEqual(converted.planVersion, 1)
        XCTAssertEqual(converted.plan.sessions.count, 1)
        XCTAssertFalse(converted.plan.isRestDay)
        let session = try XCTUnwrap(converted.plan.sessions.first)
        XCTAssertEqual(session.sport, SportID.swim)
        XCTAssertEqual(session.sessionType, .threshold)
        XCTAssertEqual(session.intensity, .hard)
        XCTAssertEqual(session.focus, "")
        XCTAssertNil(session.test)
        XCTAssertEqual(session.amount, 1600)
        XCTAssertEqual(session.unit, .meters)
        XCTAssertEqual(session.distanceMeters, 1600)
        XCTAssertEqual(session.durationMinutes, 45)
    }

    func testLegacySetsBecomeDistanceStepsWithPaceTargetOnlyWhenSet() throws {
        let converted = DayPlanV2Response(legacy: legacyResponse())
        let session = try XCTUnwrap(converted.plan.sessions.first)

        let expected: [PlanStep] = [
            PlanStep(name: "Einschwimmen", repetitions: 1, measure: .distance, distanceMeters: 400, restSeconds: 0, instructions: "locker"),
            PlanStep(
                name: "Hauptsatz", repetitions: 6, measure: .distance, distanceMeters: 200,
                targetType: .pacePerHundredMeters, targetValue: 105, restSeconds: 30, instructions: "gleichmäßig",
                cue: "Zug lang", equipment: ["pull_buoy"]
            )
        ]
        XCTAssertEqual(session.steps, expected)
        // Ohne Pace kein Ziel.
        XCTAssertNil(session.steps[0].targetType)
        XCTAssertNil(session.steps[0].targetValue)
        XCTAssertNil(session.steps[0].durationSeconds)
        XCTAssertEqual(session.equipmentNeeded, ["pull_buoy"])
    }

    func testLegacyResponseFieldsAreCarriedOver() {
        let original = legacyResponse()
        let converted = DayPlanV2Response(legacy: original)

        XCTAssertEqual(converted.source, .fallback)
        XCTAssertEqual(converted.date, "2026-09-29")
        XCTAssertEqual(converted.generatedAt, TestFixtures.now)
        XCTAssertTrue(converted.stale)
        XCTAssertEqual(converted.adjustments, ["Umfang gekürzt"])
        XCTAssertEqual(converted.fallbackReason, "timeout")
        XCTAssertEqual(converted.wishes, "kurz")
        XCTAssertEqual(converted.plan.rationale, "Schwelle halten.")
        XCTAssertEqual(converted.plan.coachNotes, ["Auf lockere Atmung achten."])
    }

    func testLegacyRestDayHasNoSessions() {
        let converted = DayPlanV2Response(legacy: legacyRestDay())

        let expected = DayPlanV2Response(
            planVersion: 1,
            source: .claude,
            date: "2026-10-01",
            generatedAt: TestFixtures.now,
            stale: false,
            plan: DayPlanV2(rationale: "Erholung nach dem harten Tag.", sessions: [], coachNotes: ["Früh schlafen."]),
            adjustments: [],
            fallbackReason: nil,
            wishes: "frei"
        )
        XCTAssertEqual(converted, expected)
        XCTAssertTrue(converted.plan.isRestDay)
    }

    func testFixtureResponseConvertsToTheSameSession() throws {
        let converted = DayPlanV2Response(legacy: TestFixtures.response())
        let session = try XCTUnwrap(converted.plan.sessions.first)

        XCTAssertEqual(session.sessionType, .technique)
        XCTAssertEqual(session.intensity, .easy)
        XCTAssertEqual(session.amount, 800)
        XCTAssertEqual(session.durationMinutes, 25)
        XCTAssertEqual(session.steps.map(\.totalMeters), [800])
        XCTAssertNil(converted.fallbackReason)
    }

    // MARK: - Plan v2 für die Watch

    func testLegacyPlanSurvivesTheRoundTripToTheWatch() {
        // v1 → v2 → v1 ergibt wieder denselben Plan.
        let original = legacyResponse()
        XCTAssertEqual(DayPlanV2Response(legacy: original).watchPlan(), original)

        let fixture = TestFixtures.response()
        XCTAssertEqual(DayPlanV2Response(legacy: fixture).watchPlan(), fixture)
    }

    func testSwimSessionBecomesTheWatchPlanAndDurationStepsBecomeMeters() {
        let swim = DaySession(
            sport: .swim,
            sessionType: .intervals,
            intensity: .hard,
            focus: "Tempo",
            amount: 1500,
            unit: .meters,
            distanceMeters: 1499.6,
            durationMinutes: 44.6,
            steps: [
                // 300 s × 0,8 m/s = 240 m → auf 25 m gerundet 250 m; Pulszone ist keine Pace.
                PlanStep(name: "Einschwimmen", repetitions: 1, measure: .duration, durationSeconds: 300, targetType: .heartRateZone, targetValue: 2, cue: "Locker"),
                // Strecke bleibt, Pace bleibt.
                PlanStep(
                    name: "Hauptsatz", repetitions: 8, measure: .distance, distanceMeters: 100,
                    targetType: .pacePerHundredMeters, targetValue: 100, restSeconds: 15, instructions: "schnell", equipment: ["fins"]
                ),
                // 600 s × 0,8 m/s = 480 m → 475 m.
                PlanStep(name: "Ausschwimmen", repetitions: 1, measure: .duration, durationSeconds: 600),
                // Weder Strecke noch Dauer: 0 m.
                PlanStep(name: "Dehnen", repetitions: 1, measure: nil)
            ]
        )
        // Schwimmen steht an zweiter Stelle; die Watch bekommt trotzdem die Schwimmeinheit.
        let day = response([minutesSession(.run, 30), swim])

        let watch = day.watchPlan()

        let expectedPlan = TrainingPlan(
            sessionType: .intervals,
            intensity: .hard,
            rationale: "Zwei Einheiten.",
            totalDistanceMeters: 1500,
            estimatedDurationMinutes: 45,
            sets: [
                PlanSet(name: "Einschwimmen", repetitions: 1, distanceMeters: 250, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: "", equipment: [], cue: "Locker"),
                PlanSet(name: "Hauptsatz", repetitions: 8, distanceMeters: 100, targetPaceSecondsPerHundredMeters: 100, restSeconds: 15, instructions: "schnell", equipment: ["fins"], cue: ""),
                PlanSet(name: "Ausschwimmen", repetitions: 1, distanceMeters: 475, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: ""),
                PlanSet(name: "Dehnen", repetitions: 1, distanceMeters: 0, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: "")
            ],
            coachNotes: ["Viel trinken."]
        )
        XCTAssertEqual(watch.plan, expectedPlan)
        XCTAssertFalse(watch.plan.isRestDay)
    }

    func testDurationStepsAreConvertedWithTheSwimModulesTypicalSpeed() {
        let speed = SwimModule().typicalSpeedMetersPerSecond
        let swim = DaySession(
            sport: .swim, sessionType: .endurance, intensity: .easy, focus: "", amount: 1000, unit: .meters,
            distanceMeters: 1000, durationMinutes: 21,
            steps: [PlanStep(name: "Dauer", repetitions: 2, measure: .duration, durationSeconds: 90)]
        )

        let sets = response([swim]).watchPlan().plan.sets

        // 90 s × Tempo, auf volle 25 m gerundet (72 m → 75 m).
        let expected = Int((90 * speed / 25).rounded()) * 25
        XCTAssertEqual(sets.map(\.distanceMeters), [expected])
        XCTAssertEqual(sets.map(\.distanceMeters), [75])
        XCTAssertEqual(sets.map(\.repetitions), [2])
    }

    func testWatchPlanKeepsTheResponseFields() {
        let swim = DaySession(
            sport: .swim, sessionType: .technique, intensity: .easy, focus: "", amount: 800, unit: .meters,
            distanceMeters: 800, durationMinutes: 25, steps: []
        )
        let day = response([swim])

        let watch = day.watchPlan()

        XCTAssertEqual(watch.source, .cache)
        XCTAssertEqual(watch.date, "2026-10-02")
        XCTAssertEqual(watch.generatedAt, TestFixtures.now)
        XCTAssertFalse(watch.stale)
        XCTAssertEqual(watch.adjustments, ["Rad gekürzt"])
        XCTAssertNil(watch.fallbackReason)
        XCTAssertEqual(watch.wishes, "Koppeltraining")
        XCTAssertEqual(watch.plan.sets, [])
    }

    func testWithoutSwimmingTheWatchGetsARestDayThatNamesTheOtherSessions() {
        let day = response([minutesSession(.bike, 60), minutesSession(.run, 30)])

        let watch = day.watchPlan()

        XCTAssertTrue(watch.plan.rationale.hasPrefix("Heute kein Schwimmen. Auf dem iPhone: "))
        XCTAssertEqual(watch.plan.rationale, "Heute kein Schwimmen. Auf dem iPhone: Radfahren · 60 min, Laufen · 30 min.")
        let expectedPlan = TrainingPlan(
            sessionType: .rest,
            intensity: .rest,
            rationale: "Heute kein Schwimmen. Auf dem iPhone: Radfahren · 60 min, Laufen · 30 min.",
            totalDistanceMeters: 0,
            estimatedDurationMinutes: 0,
            sets: [],
            coachNotes: ["Viel trinken."]
        )
        XCTAssertEqual(watch.plan, expectedPlan)
        XCTAssertTrue(watch.plan.isRestDay)
        // Die übrigen Felder bleiben.
        XCTAssertEqual(watch.wishes, "Koppeltraining")
        XCTAssertEqual(watch.adjustments, ["Rad gekürzt"])
    }

    func testRestDayTextUsesTheGivenRegistry() throws {
        let day = response([minutesSession(.bike, 60)])
        let swimOnly = try SportRegistry(modules: [SwimModule()])

        // Eine Sportart, die die Registry nicht kennt, steht mit ihrer Kennung da.
        XCTAssertEqual(day.watchPlan(registry: swimOnly).plan.rationale, "Heute kein Schwimmen. Auf dem iPhone: bike · 60 min.")
        XCTAssertEqual(day.watchPlan().plan.rationale, "Heute kein Schwimmen. Auf dem iPhone: Radfahren · 60 min.")
        XCTAssertEqual(
            day.watchPlan(registry: .standard).plan.rationale,
            "Heute kein Schwimmen. Auf dem iPhone: " + PlanV2Formatting.sessionTitle(sport: .bike, amount: 60, unit: .minutes) + "."
        )
        XCTAssertEqual(
            response([minutesSession("kayak", 40)]).watchPlan().plan.rationale,
            "Heute kein Schwimmen. Auf dem iPhone: kayak · 40 min."
        )
    }

    func testARealRestDayIsARestDayOnTheWatch() {
        let day = response([], rationale: "Erholung.", notes: ["Schlafen."])

        let watch = day.watchPlan()

        XCTAssertEqual(watch.plan.rationale, "Heute ist Ruhetag.")
        XCTAssertEqual(watch.plan.sessionType, .rest)
        XCTAssertEqual(watch.plan.intensity, .rest)
        XCTAssertEqual(watch.plan.totalDistanceMeters, 0)
        XCTAssertEqual(watch.plan.estimatedDurationMinutes, 0)
        XCTAssertEqual(watch.plan.sets, [])
        XCTAssertEqual(watch.plan.coachNotes, ["Schlafen."])
        XCTAssertTrue(watch.plan.isRestDay)
    }

    func testLegacyRestDayStaysARestDayOnTheWatch() {
        let watch = DayPlanV2Response(legacy: legacyRestDay()).watchPlan()

        XCTAssertTrue(watch.plan.isRestDay)
        XCTAssertEqual(watch.plan.rationale, "Heute ist Ruhetag.")
        XCTAssertEqual(watch.plan.coachNotes, ["Früh schlafen."])
        XCTAssertEqual(watch.wishes, "frei")
        XCTAssertEqual(watch.date, "2026-10-01")
    }
}
