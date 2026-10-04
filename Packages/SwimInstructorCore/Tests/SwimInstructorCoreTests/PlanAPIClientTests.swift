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

    func testEquipmentIsSentWhenGivenIncludingAnEmptyList() async throws {
        let transport = StubTransport(status: 200, body: TestFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)

        _ = try await client.fetchPlan(for: TestFixtures.snapshot, options: PlanRequestOptions(equipment: ["pull_buoy", "fins"]))
        _ = try await client.fetchPlan(for: TestFixtures.snapshot, options: PlanRequestOptions(equipment: []))
        _ = try await client.fetchTodayPlan(for: TestFixtures.snapshot)

        let bodies = try transport.requests.map { request -> [String: Any] in
            try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        }
        XCTAssertEqual(bodies[0]["equipment"] as? [String], ["pull_buoy", "fins"])
        XCTAssertEqual(bodies[1]["equipment"] as? [String], [])
        XCTAssertNil(bodies[2]["equipment"])
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

    func testNetworkErrorsAreDescribedInGerman() {
        XCTAssertTrue(PlanAPIClient.describe(URLError(.cannotFindHost)).contains("auflösen"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.dnsLookupFailed)).contains("DNS"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.notConnectedToInternet)).contains("keine Internetverbindung"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.timedOut)).contains("rechtzeitig"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.cannotConnectToHost)).contains("nicht erreichbar"))
        XCTAssertTrue(PlanAPIClient.describe(URLError(.serverCertificateUntrusted)).contains("Zertifikat"))
        // Alles andere behält den Systemtext.
        XCTAssertEqual(PlanAPIClient.describe(URLError(.badURL)), URLError(.badURL).localizedDescription)
        XCTAssertEqual(PlanAPIClient.describe(TestError(message: "sonst")), "sonst")
    }

    func testHostLookupFailureReachesTheUserAsGermanText() async {
        let client = PlanAPIClient(configuration: configuration, transport: StubTransport(error: URLError(.cannotFindHost)))
        do {
            _ = try await client.fetchTodayPlan(for: TestFixtures.snapshot)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertTrue(error.localizedDescription.hasPrefix("Keine Verbindung zum Server: Der Servername lässt sich nicht auflösen"))
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

    // MARK: - Wochenplan und Tagesvorgabe

    func testDayPlanTargetGoesToTheServerInSnakeCase() async throws {
        let transport = StubTransport(status: 200, body: TestFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)
        let target = DayPlanTarget(sessionType: .technique, intensity: .easy, targetDistanceMeters: 1000, focus: "Technik")

        _ = try await client.fetchPlan(for: TestFixtures.snapshot, options: PlanRequestOptions(dayPlan: target))
        _ = try await client.fetchTodayPlan(for: TestFixtures.snapshot)

        let bodies = try transport.requests.map { request -> [String: Any] in
            try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        }
        let sent = try XCTUnwrap(bodies[0]["day_plan"] as? [String: Any])
        XCTAssertEqual(sent["session_type"] as? String, "technique")
        XCTAssertEqual(sent["intensity"] as? String, "easy")
        XCTAssertEqual(sent["target_distance_meters"] as? Int, 1000)
        XCTAssertEqual(sent["focus"] as? String, "Technik")
        XCTAssertNil(bodies[1]["day_plan"])
    }

    func testWeekPlanRequestAndResponse() async throws {
        let transport = StubTransport(status: 200, body: WeekFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)
        let request = WeekPlanRequest(
            snapshot: TestFixtures.snapshot,
            weekStart: "2026-09-28",
            fromDate: "2026-09-30",
            today: "2026-09-30",
            unavailableDates: ["2026-10-02"],
            swumThisWeek: [SwumDay(date: "2026-09-28", meters: 900)],
            wishes: "  mehr Technik  "
        )

        let response = try await client.fetchWeekPlan(request)

        XCTAssertEqual(response.weekPlan.days.count, 3)
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.test/v1/plan/week")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
        XCTAssertEqual(sent.timeoutInterval, PlanAPIClient.planTimeout)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(sent.httpBody)) as? [String: Any])
        XCTAssertEqual(body["week_start"] as? String, "2026-09-28")
        XCTAssertEqual(body["from_date"] as? String, "2026-09-30")
        XCTAssertEqual(body["today"] as? String, "2026-09-30")
        XCTAssertEqual(body["unavailable_dates"] as? [String], ["2026-10-02"])
        XCTAssertEqual(body["wishes"] as? String, "mehr Technik")
        let swum = try XCTUnwrap(body["swum_this_week"] as? [[String: Any]])
        XCTAssertEqual(swum.first?["date"] as? String, "2026-09-28")
        XCTAssertEqual(swum.first?["meters"] as? Double, 900)
        XCTAssertNotNil(body["snapshot"] as? [String: Any])
    }

    func testWeekPlanRequestCarriesTheEquipment() async throws {
        let transport = StubTransport(status: 200, body: WeekFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)

        _ = try await client.fetchWeekPlan(WeekPlanRequest(snapshot: TestFixtures.snapshot, weekStart: "2026-09-28", fromDate: "2026-09-28", today: "2026-09-28", equipment: ["kickboard"]))
        _ = try await client.fetchWeekPlan(WeekPlanRequest(snapshot: TestFixtures.snapshot, weekStart: "2026-09-28", fromDate: "2026-09-28", today: "2026-09-28"))

        let bodies = try transport.requests.map { request -> [String: Any] in
            try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        }
        XCTAssertEqual(bodies[0]["equipment"] as? [String], ["kickboard"])
        XCTAssertNil(bodies[1]["equipment"])
    }

    func testRollingWeekPlanRequestHasNoWeekStartAndCarriesTheLastWeekAndTheMacroWeeks() async throws {
        let transport = StubTransport(status: 200, body: WeekFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)
        let macro = MacroFixtures.week("2026-09-28", meters: 3500, sessions: 3, deload: false, focus: "Ausdauer", phase: .specific)

        _ = try await client.fetchWeekPlan(WeekPlanRequest(
            snapshot: TestFixtures.snapshot,
            weekStart: nil,
            fromDate: "2026-09-30",
            today: "2026-09-30",
            recentSwim: [SwumDay(date: "2026-09-27", meters: 1200)],
            macroWeeks: [macro]
        ))
        _ = try await client.fetchWeekPlan(WeekPlanRequest(snapshot: TestFixtures.snapshot, weekStart: nil, fromDate: "2026-09-30", today: "2026-09-30"))

        let bodies = try transport.requests.map { request -> [String: Any] in
            try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        }
        XCTAssertNil(bodies[0]["week_start"])
        XCTAssertEqual(bodies[0]["from_date"] as? String, "2026-09-30")
        let recent = try XCTUnwrap(bodies[0]["recent_swim"] as? [[String: Any]])
        XCTAssertEqual(recent.first?["meters"] as? Double, 1200)
        let weeks = try XCTUnwrap(bodies[0]["macro_weeks"] as? [[String: Any]])
        XCTAssertEqual(weeks.first?["week_start"] as? String, "2026-09-28")
        XCTAssertEqual(weeks.first?["target_meters"] as? Int, 3500)
        XCTAssertEqual(weeks.first?["phase"] as? String, "specific")
        XCTAssertEqual(weeks.first?["deload"] as? Bool, false)
        XCTAssertEqual(weeks.first?["focus"] as? String, "Ausdauer")
        // Ohne Gesamtplan und Vorwoche fehlen die Felder.
        XCTAssertNil(bodies[1]["macro_weeks"])
        XCTAssertNil(bodies[1]["recent_swim"])
    }

    func testMacroPlanRequestAndResponse() async throws {
        let transport = StubTransport(status: 200, body: MacroFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)

        let response = try await client.fetchMacroPlan(MacroPlanRequest(snapshot: TestFixtures.snapshot, today: "2026-09-30"))

        XCTAssertEqual(response.plan.weeks.count, 5)
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.test/v1/plan/macro")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
        XCTAssertEqual(sent.timeoutInterval, PlanAPIClient.macroTimeout)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(sent.httpBody)) as? [String: Any])
        XCTAssertEqual(body["today"] as? String, "2026-09-30")
        XCTAssertNotNil(body["snapshot"] as? [String: Any])
    }

    func testMacroPlanErrorsAreMappedLikeThePlanErrors() async {
        func failure(status: Int, body: String) async -> PlanAPIError? {
            let client = PlanAPIClient(configuration: configuration, transport: StubTransport(status: status, body: body))
            do {
                _ = try await client.fetchMacroPlan(MacroPlanRequest(snapshot: TestFixtures.snapshot, today: "2026-09-30"))
                return nil
            } catch {
                return error as? PlanAPIError
            }
        }

        let unauthorized = await failure(status: 401, body: "{}")
        let invalid = await failure(status: 400, body: #"{"error":"invalid_request","details":[{"path":"today","message":"kaputt"}]}"#)
        let unavailable = await failure(status: 503, body: #"{"error":"plan_unavailable","reason":"timeout"}"#)
        let garbage = await failure(status: 200, body: "kein json")

        XCTAssertEqual(unauthorized, .unauthorized)
        XCTAssertEqual(invalid, .invalidRequest(details: ["today: kaputt"]))
        XCTAssertEqual(unavailable, .planUnavailable(reason: "timeout"))
        if case .invalidResponse = garbage {} else { XCTFail("erwartet: unverständliche Antwort, bekam \(String(describing: garbage))") }
    }

    func testWeekPlanRequestWithoutWishSendsNone() async throws {
        let transport = StubTransport(status: 200, body: WeekFixtures.responseJSON)
        let client = PlanAPIClient(configuration: configuration, transport: transport)

        _ = try await client.fetchWeekPlan(WeekPlanRequest(snapshot: TestFixtures.snapshot, weekStart: "2026-09-28", fromDate: "2026-09-28", today: "2026-09-28", wishes: "   "))

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(transport.requests.first?.httpBody)) as? [String: Any])
        XCTAssertNil(body["wishes"])
        XCTAssertEqual(body["unavailable_dates"] as? [String], [])
    }

    func testWeekPlanErrorsAreMappedLikeThePlanErrors() async {
        for (status, body, expected) in [
            (401, "{}", PlanAPIError.unauthorized),
            (400, #"{"error":"invalid_request","details":[{"path":"week_start","message":"muss ein Montag sein"}]}"#, PlanAPIError.invalidRequest(details: ["week_start: muss ein Montag sein"])),
            (503, #"{"error":"plan_unavailable","reason":"budget_exceeded"}"#, PlanAPIError.planUnavailable(reason: "budget_exceeded")),
            (500, "{}", PlanAPIError.server(status: 500))
        ] {
            let client = PlanAPIClient(configuration: configuration, transport: StubTransport(status: status, body: body))
            do {
                _ = try await client.fetchWeekPlan(WeekPlanRequest(snapshot: TestFixtures.snapshot, weekStart: "2026-09-28", fromDate: "2026-09-28", today: "2026-09-28"))
                XCTFail("Fehler erwartet für Status \(status)")
            } catch let error as PlanAPIError {
                XCTAssertEqual(error, expected)
            } catch {
                XCTFail("falscher Fehlertyp: \(error)")
            }
        }
    }

    func testWeekPlanGarbageAndNetworkFailure() async {
        let garbage = PlanAPIClient(configuration: configuration, transport: StubTransport(status: 200, body: "<html>"))
        do {
            _ = try await garbage.fetchWeekPlan(WeekPlanRequest(snapshot: TestFixtures.snapshot, weekStart: "2026-09-28", fromDate: "2026-09-28", today: "2026-09-28"))
            XCTFail("Fehler erwartet")
        } catch let error as PlanAPIError {
            guard case .invalidResponse = error else { return XCTFail("falscher Fehler: \(error)") }
        } catch {
            XCTFail("falscher Fehlertyp: \(error)")
        }

        let offline = PlanAPIClient(configuration: configuration, transport: StubTransport(error: URLError(.notConnectedToInternet)))
        do {
            _ = try await offline.fetchWeekPlan(WeekPlanRequest(snapshot: TestFixtures.snapshot, weekStart: "2026-09-28", fromDate: "2026-09-28", today: "2026-09-28"))
            XCTFail("Fehler erwartet")
        } catch let error as PlanAPIError {
            guard case .network = error else { return XCTFail("falscher Fehler: \(error)") }
        } catch {
            XCTFail("falscher Fehlertyp: \(error)")
        }
    }

    func testPlanUnavailableTextNamesTheReason() {
        XCTAssertTrue(PlanAPIError.planUnavailable(reason: "budget_exceeded").errorDescription?.contains("Tageslimit") == true)
        XCTAssertTrue(PlanAPIError.planUnavailable(reason: "not_configured").errorDescription?.contains("nicht eingerichtet") == true)
        XCTAssertTrue(PlanAPIError.planUnavailable(reason: "timeout").errorDescription?.contains("nicht erreichbar") == true)
        XCTAssertTrue(PlanAPIError.planUnavailable(reason: nil).errorDescription?.hasPrefix("Kein neuer Plan") == true)
    }
}

