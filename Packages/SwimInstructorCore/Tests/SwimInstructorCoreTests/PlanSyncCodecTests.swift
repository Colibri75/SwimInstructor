import XCTest
@testable import SwimInstructorCore

final class PlanSyncCodecTests: XCTestCase {
    private func dayPlan() throws -> DayPlanV2Response {
        try PlanCoding.jsonDecoder().decode(DayPlanV2Response.self, from: RepoPaths.contractData("wire/plan-v2-today-response.json"))
    }

    func testRoundTripKeepsAllSessions() throws {
        let original = try dayPlan()
        XCTAssertEqual(original.plan.sessions.map(\.sport), [.swim, .bike])

        let context = try PlanSyncCodec.context(for: original)

        XCTAssertEqual(PlanSyncCodec.dayPlan(from: context), original)
    }

    func testContextContainsOnlyPropertyListTypes() throws {
        // WatchConnectivity nimmt nur Property-List-Werte an, sonst wirft updateApplicationContext.
        let context = try PlanSyncCodec.context(for: try dayPlan())

        XCTAssertTrue(PropertyListSerialization.propertyList(context, isValidFor: .binary))
    }

    func testRoundTripKeepsFallbackReason() throws {
        let original = try dayPlan()
        let fallback = DayPlanV2Response(
            source: .fallback, date: original.date, generatedAt: original.generatedAt, stale: true, plan: original.plan,
            adjustments: original.adjustments, fallbackReason: "timeout", wishes: original.wishes
        )

        let decoded = PlanSyncCodec.dayPlan(from: try PlanSyncCodec.context(for: fallback))

        XCTAssertEqual(decoded, fallback)
        XCTAssertEqual(decoded?.fallbackReason, "timeout")
    }

    func testEmptyForeignOrBrokenContextYieldsNil() {
        XCTAssertNil(PlanSyncCodec.dayPlan(from: [:]))
        XCTAssertNil(PlanSyncCodec.dayPlan(from: ["plan_v2": Data("kaputt".utf8), "version": 1]))
        XCTAssertNil(PlanSyncCodec.dayPlan(from: ["plan_v2": "kein Data", "version": 1]))
    }

    func testUnknownFormatVersionIsIgnored() throws {
        var context = try PlanSyncCodec.context(for: try dayPlan())
        context["version"] = 2

        XCTAssertNil(PlanSyncCodec.dayPlan(from: context))
    }

    func testPlanRequestIsRecognized() {
        XCTAssertTrue(PlanSyncCodec.isPlanRequest(PlanSyncCodec.planRequest))
        XCTAssertFalse(PlanSyncCodec.isPlanRequest([:]))
        XCTAssertFalse(PlanSyncCodec.isPlanRequest(["request": "etwas anderes"]))
    }

    /// So landet der Plan auch auf der Uhr: mit Vorgabe der 14 Tage (nur in der App) und Kraftblock mit Übungen.
    private func planWithTargetAndExtras(date: String? = nil, source: PlanSource? = nil) throws -> DayPlanV2Response {
        let original = try dayPlan()
        let plan = DayPlanV2(
            rationale: original.plan.rationale,
            sessions: original.plan.sessions,
            extras: [DayExtra(kind: .strength, minutes: 20, focus: "Rumpf", exercises: [
                Exercise(name: "Unterarmstütz", sets: 3, seconds: 40, restSeconds: 30, cue: "Bauch fest", instructions: "Ellbogen unter den Schultern."),
                Exercise(name: "Ausfallschritt", sets: 3, reps: 10)
            ])],
            coachNotes: ["Viel trinken."]
        )
        var response = DayPlanV2Response(
            source: source ?? original.source, date: date ?? original.date, generatedAt: original.generatedAt, stale: false,
            plan: plan, adjustments: original.adjustments, wishes: original.wishes
        )
        response.requestedTarget = DayTargetV2(
            focus: "Grundlage",
            sessions: [.init(sport: .swim, sessionType: .endurance, intensity: .easy, amount: 2_000, focus: "Technik", testID: "css")],
            extras: [.init(kind: .strength, minutes: 20, focus: "Rumpf")]
        )
        return response
    }

    func testRoundTripKeepsTargetAndExtras() throws {
        let original = try planWithTargetAndExtras()

        XCTAssertEqual(PlanSyncCodec.dayPlan(from: try PlanSyncCodec.context(for: original)), original)
    }

    func testTodaysPlanIsTheReply() throws {
        let today = try planWithTargetAndExtras(date: "2026-10-16")

        let reply = PlanSyncCodec.reply(for: today, today: "2026-10-16", canPlan: true)

        XCTAssertEqual(PlanSyncCodec.dayPlan(from: reply), today)
        XCTAssertFalse(PlanSyncCodec.isPreparing(reply))
    }

    func testAnOldPlanIsNotSentAsTheNewest() throws {
        // Die iPhone-App war seit dem 11. nicht offen: Sie plant gerade, die Uhr soll das wissen statt den alten Plan zu
        // bekommen.
        let old = try planWithTargetAndExtras(date: "2026-10-11")

        let reply = PlanSyncCodec.reply(for: old, today: "2026-10-16", canPlan: true)

        XCTAssertNil(PlanSyncCodec.dayPlan(from: reply))
        XCTAssertTrue(PlanSyncCodec.isPreparing(reply))
        XCTAssertTrue(PlanSyncCodec.isPreparing(PlanSyncCodec.reply(for: nil, today: "2026-10-16", canPlan: true)))
    }

    func testAFallbackOrAPhoneThatCannotPlanSendsWhatItHas() throws {
        let fallback = try planWithTargetAndExtras(date: "2026-10-11", source: .fallback)
        let old = try planWithTargetAndExtras(date: "2026-10-11")

        XCTAssertEqual(PlanSyncCodec.dayPlan(from: PlanSyncCodec.reply(for: fallback, today: "2026-10-16", canPlan: true)), fallback)
        XCTAssertEqual(PlanSyncCodec.dayPlan(from: PlanSyncCodec.reply(for: old, today: "2026-10-16", canPlan: false)), old)
        XCTAssertTrue(PlanSyncCodec.reply(for: nil, today: "2026-10-16", canPlan: false).isEmpty)
    }

    func testPreparingIsNotAPlanAndNotAnOldFormat() {
        XCTAssertNil(PlanSyncCodec.dayPlan(from: PlanSyncCodec.preparingReply))
        XCTAssertFalse(PlanSyncCodec.isPreparing([:]))
        XCTAssertFalse(PlanSyncCodec.isPreparing(["status": "preparing", "version": 2]))
    }
}
