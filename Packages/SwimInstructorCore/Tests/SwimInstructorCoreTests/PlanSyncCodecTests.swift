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

    func testPlanRequestIsRecognized() {
        XCTAssertTrue(PlanSyncCodec.isPlanRequest(PlanSyncCodec.planRequest))
        XCTAssertFalse(PlanSyncCodec.isPlanRequest([:]))
        XCTAssertFalse(PlanSyncCodec.isPlanRequest(["request": "etwas anderes"]))
    }
}
