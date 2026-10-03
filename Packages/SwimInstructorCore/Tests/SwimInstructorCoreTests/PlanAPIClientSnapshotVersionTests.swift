import XCTest
@testable import SwimInstructorCore

/// Snapshot v2 an einen Server, der nur v1 kennt (App schon aktualisiert, Server noch nicht neu gestartet).
final class PlanAPIClientSnapshotVersionTests: XCTestCase {
    private let configuration = BackendConfiguration(baseURL: URL(string: "https://example.test")!, token: "geheim")
    private let oldServerRejection = #"{"error":"invalid_request","details":[{"path":"snapshot.schema_version","message":"Invalid input: expected 1"}]}"#

    private func v2() throws -> AthleteStateSnapshot {
        try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: RepoPaths.contractData("wire/snapshot-v2.json"))
    }

    private func sentSnapshots(_ transport: SequenceTransport) throws -> [[String: Any]] {
        try transport.requests.map { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
            return try XCTUnwrap(body["snapshot"] as? [String: Any])
        }
    }

    func testV2GoesOutAsIsToANewServer() async throws {
        let transport = SequenceTransport([(200, TestFixtures.responseJSON)])
        _ = try await PlanAPIClient(configuration: configuration, transport: transport).fetchTodayPlan(for: try v2())

        let sent = try sentSnapshots(transport)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["schema_version"] as? Int, 2)
        XCTAssertNotNil(sent[0]["training_goal"])
    }

    func testOldServerGetsTheSameRequestAgainAsV1() async throws {
        let transport = SequenceTransport([(400, oldServerRejection), (200, TestFixtures.responseJSON)])
        let client = PlanAPIClient(configuration: configuration, transport: transport)

        let response = try await client.fetchPlan(for: try v2(), options: PlanRequestOptions(wishes: "Technik"))

        XCTAssertEqual(response.plan.totalDistanceMeters, 1600)
        let sent = try sentSnapshots(transport)
        XCTAssertEqual(sent.map { $0["schema_version"] as? Int }, [2, 1])
        XCTAssertNil(sent[1]["training_goal"])
        XCTAssertNil(sent[1]["sports"])
        XCTAssertNil(sent[1]["total_load"])
        XCTAssertEqual(transport.requests.map(\.url?.path), ["/v1/plan/today", "/v1/plan/today"])
        // Der Rest der Anfrage bleibt gleich.
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(transport.requests[1].httpBody)) as? [String: Any])
        XCTAssertEqual(second["wishes"] as? String, "Technik")
    }

    func testWeekAndMacroFallBackToo() async throws {
        let week = try String(contentsOf: RepoPaths.contract("wire/plan-week-response.json"), encoding: .utf8)
        let macro = try String(contentsOf: RepoPaths.contract("wire/plan-macro-response.json"), encoding: .utf8)
        let weekTransport = SequenceTransport([(400, oldServerRejection), (200, week)])
        let macroTransport = SequenceTransport([(400, oldServerRejection), (200, macro)])

        _ = try await PlanAPIClient(configuration: configuration, transport: weekTransport)
            .fetchWeekPlan(WeekPlanRequest(snapshot: try v2(), weekStart: nil, fromDate: "2026-09-30", today: "2026-09-30"))
        _ = try await PlanAPIClient(configuration: configuration, transport: macroTransport)
            .fetchMacroPlan(MacroPlanRequest(snapshot: try v2(), today: "2026-09-30"))

        XCTAssertEqual(try sentSnapshots(weekTransport).map { $0["schema_version"] as? Int }, [2, 1])
        XCTAssertEqual(try sentSnapshots(macroTransport).map { $0["schema_version"] as? Int }, [2, 1])
    }

    func testOtherRejectionsAreNotRetried() async throws {
        let other = #"{"error":"invalid_request","details":[{"path":"snapshot.training_goal.emphasis","message":"Schwerpunkte ergeben nicht 100 %"}]}"#
        let transport = SequenceTransport([(400, other), (200, TestFixtures.responseJSON)])

        do {
            _ = try await PlanAPIClient(configuration: configuration, transport: transport).fetchTodayPlan(for: try v2())
            XCTFail("Fehler erwartet")
        } catch let error as PlanAPIError {
            XCTAssertEqual(error, .invalidRequest(details: ["snapshot.training_goal.emphasis: Schwerpunkte ergeben nicht 100 %"]))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAV1SnapshotIsNeverSentTwice() async throws {
        let transport = SequenceTransport([(400, oldServerRejection), (200, TestFixtures.responseJSON)])

        do {
            _ = try await PlanAPIClient(configuration: configuration, transport: transport).fetchTodayPlan(for: TestFixtures.snapshot)
            XCTFail("Fehler erwartet")
        } catch let error as PlanAPIError {
            XCTAssertEqual(error, .invalidRequest(details: ["snapshot.schema_version: Invalid input: expected 1"]))
        }
        XCTAssertEqual(transport.requests.count, 1)
    }
}
