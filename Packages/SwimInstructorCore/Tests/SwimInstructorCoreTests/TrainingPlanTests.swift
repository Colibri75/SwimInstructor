import XCTest
@testable import SwimInstructorCore

final class TrainingPlanTests: XCTestCase {
    func testDecodesServerResponseWithMilliseconds() throws {
        let response = try PlanResponse.jsonDecoder().decode(PlanResponse.self, from: Data(TestFixtures.responseJSON.utf8))

        XCTAssertEqual(response.source, .claude)
        XCTAssertEqual(response.date, "2026-09-30")
        XCTAssertEqual(response.generatedAt, ISO8601DateFormatter().date(from: "2026-09-30T10:00:00Z"))
        XCTAssertFalse(response.stale)
        XCTAssertNil(response.fallbackReason)
        XCTAssertEqual(response.adjustments.count, 1)
        XCTAssertEqual(response.plan.sessionType, .endurance)
        XCTAssertEqual(response.plan.intensity, .moderate)
        XCTAssertEqual(response.plan.totalDistanceMeters, 1600)
        XCTAssertEqual(response.plan.estimatedDurationMinutes, 45)
        XCTAssertEqual(response.plan.sets.count, 2)
        XCTAssertNil(response.plan.sets[0].targetPaceSecondsPerHundredMeters)
        XCTAssertEqual(response.plan.sets[1].targetPaceSecondsPerHundredMeters, 140)
        XCTAssertEqual(response.plan.sets[1].restSeconds, 30)
        XCTAssertEqual(response.plan.sets[1].totalMeters, 1200)
        XCTAssertEqual(response.plan.coachNotes, ["Auf lockere Atmung achten."])
    }

    func testDecodesFallbackAndRestDay() throws {
        let json = """
        {"source":"fallback","date":"2026-09-29","generated_at":"2026-09-29T06:00:00Z","stale":true,
         "fallback_reason":"timeout","adjustments":[],
         "plan":{"session_type":"rest","intensity":"rest","rationale":"Erholung","total_distance_meters":0,
                 "estimated_duration_minutes":0,"sets":[],"coach_notes":[]}}
        """
        let response = try PlanResponse.jsonDecoder().decode(PlanResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.source, .fallback)
        XCTAssertTrue(response.stale)
        XCTAssertEqual(response.fallbackReason, "timeout")
        XCTAssertTrue(response.plan.isRestDay)
        XCTAssertTrue(response.plan.sets.isEmpty)
    }

    /// Eine neuere Serverversion mit neuen Werten darf die App nicht zum Absturz bringen.
    func testUnknownEnumValuesFallBackToUnknown() throws {
        let json = TestFixtures.responseJSON
            .replacingOccurrences(of: "\"endurance\"", with: "\"open_water\"")
            .replacingOccurrences(of: "\"moderate\"", with: "\"all_out\"")
            .replacingOccurrences(of: "\"claude\"", with: "\"edge\"")
        let response = try PlanResponse.jsonDecoder().decode(PlanResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.plan.sessionType, .unknown)
        XCTAssertEqual(response.plan.intensity, .unknown)
        XCTAssertEqual(response.source, .unknown)
    }

    func testFileCacheRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FilePlanCache(fileURL: directory.appendingPathComponent("nested/last-plan.json"))

        XCTAssertNil(cache.load())
        let response = try PlanResponse.jsonDecoder().decode(PlanResponse.self, from: Data(TestFixtures.responseJSON.utf8))
        try cache.save(response)

        XCTAssertEqual(cache.load(), response)
    }

    func testFileCacheIgnoresCorruptFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("kein json".utf8).write(to: file)

        XCTAssertNil(FilePlanCache(fileURL: file).load())
    }
}
