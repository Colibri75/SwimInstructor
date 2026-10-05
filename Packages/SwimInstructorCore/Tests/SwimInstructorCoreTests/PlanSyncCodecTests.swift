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
}
