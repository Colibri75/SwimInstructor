import XCTest
@testable import SwimInstructorCore

final class PlanAPIClientTests: XCTestCase {
    private let configuration = BackendConfiguration(baseURL: URL(string: "https://example.test")!, token: "geheim")

    func testPostsSnapshotWithTokenToPlanRoute() async throws {
        let transport = StubTransport(status: 200, body: TestFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)

        let response = try await client.fetchTodayPlan(for: TestFixtures.snapshot)

        XCTAssertEqual(response.plan.totalDistanceMeters, 1600)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/plan/today")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, PlanAPIClient.planTimeout)

        // Body ist {"snapshot": {...}} mit snake_case-Schlüsseln, so wie der Server ihn prüft.
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Array(json.keys), ["snapshot"])
        let snapshot = try XCTUnwrap(json["snapshot"] as? [String: Any])
        XCTAssertEqual(snapshot["schema_version"] as? Int, 1)
        XCTAssertNotNil(snapshot["generated_at"] as? String)
        let volume = try XCTUnwrap(snapshot["volume"] as? [String: Any])
        XCTAssertEqual(volume["last_seven_days_meters"] as? Double, 1500)
    }

    func testNewPlanRequestAsksTheServerToRegenerate() async throws {
        let transport = StubTransport(status: 200, body: TestFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)

        _ = try await client.fetchNewPlan(for: TestFixtures.snapshot)

        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["regenerate"] as? Bool, true)
        XCTAssertNotNil(json["snapshot"] as? [String: Any])
    }

    func testWishIsSentTrimmedAndOnlyWhenPresent() async throws {
        let transport = StubTransport(status: 200, body: TestFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)

        _ = try await client.fetchPlan(for: TestFixtures.snapshot, options: PlanRequestOptions(wishes: "  Heute nur Technik \n"))
        _ = try await client.fetchPlan(for: TestFixtures.snapshot, options: PlanRequestOptions(wishes: "   "))
        _ = try await client.fetchTodayPlan(for: TestFixtures.snapshot)

        let bodies = try transport.requests.map { request -> [String: Any] in
            let data = try XCTUnwrap(request.httpBody)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        XCTAssertEqual(bodies[0]["wishes"] as? String, "Heute nur Technik")
        XCTAssertNil(bodies[1]["wishes"])
        XCTAssertNil(bodies[2]["wishes"])
        XCTAssertNil(bodies[0]["regenerate"])
    }

    func testOverlongWishIsCutToTheLimit() {
        let long = String(repeating: "x", count: DailyWish.maxLength + 50)

        XCTAssertEqual(PlanAPIClient.cleaned(long)?.count, DailyWish.maxLength)
        XCTAssertNil(PlanAPIClient.cleaned(nil))
    }

    func testUnauthorized() async {
        await assertThrows(status: 401, body: #"{"error":"unauthorized"}"#, expected: .unauthorized)
    }

    func testInvalidRequestCarriesDetails() async {
        await assertThrows(
            status: 400,
            body: #"{"error":"invalid_request","details":[{"path":"snapshot.flags","message":"Invalid"}]}"#,
            expected: .invalidRequest(details: ["snapshot.flags: Invalid"])
        )
    }

    func testPlanUnavailableCarriesReason() async {
        await assertThrows(
            status: 503,
            body: #"{"error":"plan_unavailable","reason":"timeout"}"#,
            expected: .planUnavailable(reason: "timeout")
        )
    }

    func testOtherStatus() async {
        await assertThrows(status: 500, body: #"{"error":"internal_error"}"#, expected: .server(status: 500))
    }

    func testGarbageBodyIsInvalidResponse() async {
        let client = PlanAPIClient(configuration: configuration, transport: StubTransport(status: 200, body: "<html>"))
        do {
            _ = try await client.fetchTodayPlan(for: TestFixtures.snapshot)
            XCTFail("Fehler erwartet")
        } catch let error as PlanAPIError {
            guard case .invalidResponse = error else { return XCTFail("falscher Fehler: \(error)") }
        } catch {
            XCTFail("falscher Fehlertyp: \(error)")
        }
    }

    func testNetworkFailure() async {
        let client = PlanAPIClient(
            configuration: configuration,
            transport: StubTransport(error: URLError(.notConnectedToInternet))
        )
        do {
            _ = try await client.fetchTodayPlan(for: TestFixtures.snapshot)
            XCTFail("Fehler erwartet")
        } catch let error as PlanAPIError {
            guard case .network = error else { return XCTFail("falscher Fehler: \(error)") }
        } catch {
            XCTFail("falscher Fehlertyp: \(error)")
        }
    }

    func testCheckConnectionUsesStatusRoute() async throws {
        let transport = StubTransport(status: 200, body: #"{"status":"authenticated"}"#)
        try await PlanAPIClient(configuration: configuration, transport: transport).checkConnection()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/status")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
    }

    func testCheckConnectionRejectedToken() async {
        let client = PlanAPIClient(configuration: configuration, transport: StubTransport(status: 401, body: "{}"))
        do {
            try await client.checkConnection()
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error as? PlanAPIError, .unauthorized)
        }
    }

    private func assertThrows(status: Int, body: String, expected: PlanAPIError, line: UInt = #line) async {
        let client = PlanAPIClient(configuration: configuration, transport: StubTransport(status: status, body: body))
        do {
            _ = try await client.fetchTodayPlan(for: TestFixtures.snapshot)
            XCTFail("Fehler erwartet", line: line)
        } catch {
            XCTAssertEqual(error as? PlanAPIError, expected, line: line)
        }
    }
}
