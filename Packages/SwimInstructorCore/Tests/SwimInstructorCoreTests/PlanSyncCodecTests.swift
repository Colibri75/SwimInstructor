import XCTest
@testable import SwimInstructorCore

final class PlanSyncCodecTests: XCTestCase {
    func testRoundTripKeepsWholeResponse() throws {
        let original = try PlanResponse.jsonDecoder().decode(PlanResponse.self, from: Data(TestFixtures.responseJSON.utf8))

        let context = try PlanSyncCodec.context(for: original)

        XCTAssertEqual(PlanSyncCodec.response(from: context), original)
    }

    func testRoundTripKeepsFallbackReason() throws {
        let original = TestFixtures.response(date: "2026-09-29", source: .fallback, stale: true)

        let decoded = PlanSyncCodec.response(from: try PlanSyncCodec.context(for: original))

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded?.fallbackReason, "timeout")
    }

    func testContextContainsOnlyPropertyListTypes() throws {
        // WatchConnectivity nimmt nur Property-List-Werte an, sonst wirft updateApplicationContext.
        let context = try PlanSyncCodec.context(for: TestFixtures.response())

        XCTAssertTrue(PropertyListSerialization.propertyList(context, isValidFor: .binary))
    }

    func testEmptyForeignOrBrokenContextYieldsNil() {
        XCTAssertNil(PlanSyncCodec.response(from: [:]))
        XCTAssertNil(PlanSyncCodec.response(from: ["plan": Data("kaputt".utf8), "version": 1]))
        XCTAssertNil(PlanSyncCodec.response(from: ["plan": "kein Data", "version": 1]))
    }

    func testUnknownFormatVersionIsIgnored() throws {
        var context = try PlanSyncCodec.context(for: TestFixtures.response())
        context["version"] = 2

        XCTAssertNil(PlanSyncCodec.response(from: context))
    }

    // MARK: - Tagesplan v2 (ab T5)

    private func dayPlan() throws -> DayPlanV2Response {
        try PlanResponse.jsonDecoder().decode(DayPlanV2Response.self, from: RepoPaths.contractData("wire/plan-v2-today-response.json"))
    }

    func testDayPlanV2RoundTripKeepsAllSessions() throws {
        let original = try dayPlan()
        XCTAssertEqual(original.plan.sessions.map(\.sport), [.swim, .bike])

        let context = try PlanSyncCodec.context(for: original)

        XCTAssertEqual(PlanSyncCodec.dayPlan(from: context), original)
        XCTAssertTrue(PropertyListSerialization.propertyList(context, isValidFor: .binary))
    }

    func testDayPlanV2ContextStillCarriesPlanV1ForOlderWatches() throws {
        let original = try dayPlan()

        let context = try PlanSyncCodec.context(for: original)

        XCTAssertEqual(PlanSyncCodec.response(from: context), original.watchPlan())
    }

    func testPlanV1FromAnOlderPhoneBecomesADayPlan() throws {
        let legacy = TestFixtures.response()

        let dayPlan = PlanSyncCodec.dayPlan(from: try PlanSyncCodec.context(for: legacy))

        XCTAssertEqual(dayPlan, DayPlanV2Response(legacy: legacy))
        XCTAssertEqual(dayPlan?.plan.sessions.map(\.sport), [.swim])
    }

    func testBrokenPlanV2FallsBackToPlanV1() throws {
        let original = try dayPlan()
        var context = try PlanSyncCodec.context(for: original)
        context["plan_v2"] = Data("kaputt".utf8)

        XCTAssertEqual(PlanSyncCodec.dayPlan(from: context), DayPlanV2Response(legacy: original.watchPlan()))
    }

    func testDayPlanIgnoresEmptyOrNewerContexts() throws {
        XCTAssertNil(PlanSyncCodec.dayPlan(from: [:]))

        var newer = try PlanSyncCodec.context(for: try dayPlan())
        newer["version"] = 2
        XCTAssertNil(PlanSyncCodec.dayPlan(from: newer))
    }

    func testPlanRequestIsRecognized() {
        XCTAssertTrue(PlanSyncCodec.isPlanRequest(PlanSyncCodec.planRequest))
        XCTAssertFalse(PlanSyncCodec.isPlanRequest([:]))
        XCTAssertFalse(PlanSyncCodec.isPlanRequest(["request": "etwas anderes"]))
    }
}
