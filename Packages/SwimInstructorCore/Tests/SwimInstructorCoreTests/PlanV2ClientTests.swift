import XCTest
@testable import SwimInstructorCore

/// Plan v2 über `PlanAPIClient`: was an den Server geht und wie die Antworten ankommen.
final class PlanV2ClientTests: XCTestCase {
    private let configuration = BackendConfiguration(baseURL: URL(string: "https://example.test")!, token: "geheim")

    // MARK: - Hilfen

    private func makeClient(_ transport: HTTPTransport) -> PlanAPIClient {
        PlanAPIClient(configuration: configuration, transport: transport)
    }

    private static func contract(_ file: String) throws -> String {
        String(decoding: try RepoPaths.contractData("wire/\(file)"), as: UTF8.self)
    }

    private static func body(_ request: URLRequest?) throws -> [String: Any] {
        let data = try XCTUnwrap(request?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Der Fehler einer Anfrage, `nil` bei Erfolg.
    private static func failure<Response>(_ operation: () async throws -> Response) async -> Error? {
        do {
            _ = try await operation()
            return nil
        } catch {
            return error
        }
    }

    private static func isInvalidResponse(_ error: Error?) -> Bool {
        guard let apiError = error as? PlanAPIError, case .invalidResponse = apiError else { return false }
        return true
    }

    private static func macroWeek(_ weekStart: String) -> MacroWeekV2 {
        MacroWeekV2(
            weekStart: weekStart,
            phase: .specific,
            deload: false,
            focus: "Wettkampfnah",
            totalMinutes: 210,
            load: 190,
            sports: [MacroSportVolume(sport: .swim, unit: .meters, amount: 3500, minutes: 70, distanceMeters: 3500, sessions: 2)],
            tests: [MacroTestSlot(sport: .bike, testID: "threshold_30min", displayName: "30-Minuten-Test")]
        )
    }

    private static func macroPlan(rounds: [MacroFeedbackRound] = [], rationale: String = "Sechs Wochen bis zum Ziel.") -> MacroPlanV2 {
        MacroPlanV2(
            goalKey: "ziel",
            goalDay: "2026-11-08",
            generatedAt: TestFixtures.now,
            rationale: rationale,
            weeks: [macroWeek("2026-10-05"), macroWeek("2026-09-28")],
            feedbackRounds: rounds
        )
    }

    private func dayFailure(status: Int, body: String) async -> Error? {
        let client = makeClient(StubTransport(status: status, body: body))
        let request = DayPlanV2Request(snapshot: TestFixtures.snapshot)
        return await Self.failure { try await client.fetchDayPlanV2(request) }
    }

    // MARK: - Tagesplan

    func testDayPlanSendsEverythingInSnakeCase() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-today-response.json"))
        let settings = TestSettings(offer: true, intervalWeeks: 8, preferred: [TestSettings.Preference(sport: .bike, testID: "threshold_30min")])
        let target = DayTargetV2(focus: "Technik und Test", sessions: [
            DayTargetV2.Session(sport: .swim, sessionType: .technique, intensity: .easy, amount: 500, focus: "Lange Züge"),
            DayTargetV2.Session(sport: .bike, sessionType: .test, intensity: .hard, amount: 58, focus: "30-Minuten-Test", testID: "threshold_30min")
        ])
        let request = DayPlanV2Request(
            snapshot: TestFixtures.snapshot,
            regenerate: true,
            wishes: "  heute etwas Technik \n",
            dayPlan: target,
            equipment: ["pull_buoy"],
            recentTraining: [RecentTrainingEntry(date: "2026-09-29", sport: .run, minutes: 45, meters: 8000, hard: true)],
            testSettings: settings
        )

        let response = try await makeClient(transport).fetchDayPlanV2(request)

        XCTAssertEqual(response.plan.sessions.map(\.sport), [.swim, .bike])
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.test/v1/plan/today")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sent.timeoutInterval, PlanAPIClient.planTimeout)

        let body = try Self.body(sent)
        XCTAssertEqual(body["plan_version"] as? Int, 2)
        XCTAssertEqual(body["regenerate"] as? Bool, true)
        XCTAssertEqual(body["wishes"] as? String, "heute etwas Technik")
        XCTAssertEqual(body["equipment"] as? [String], ["pull_buoy"])
        XCTAssertNotNil(body["snapshot"] as? [String: Any])

        let testSettings = try XCTUnwrap(body["test_settings"] as? [String: Any])
        XCTAssertEqual(testSettings["offer"] as? Bool, true)
        XCTAssertEqual(testSettings["interval_weeks"] as? Int, 8)
        let preferred = try XCTUnwrap(testSettings["preferred"] as? [[String: Any]])
        XCTAssertEqual(preferred.count, 1)
        XCTAssertEqual(preferred.first?["sport"] as? String, "bike")
        XCTAssertEqual(preferred.first?["test_id"] as? String, "threshold_30min")

        let training = try XCTUnwrap(body["recent_training"] as? [[String: Any]])
        XCTAssertEqual(training.count, 1)
        XCTAssertEqual(training.first?["date"] as? String, "2026-09-29")
        XCTAssertEqual(training.first?["sport"] as? String, "run")
        XCTAssertEqual(training.first?["minutes"] as? Double, 45)
        XCTAssertEqual(training.first?["meters"] as? Double, 8000)
        XCTAssertEqual(training.first?["hard"] as? Bool, true)

        let dayPlan = try XCTUnwrap(body["day_plan"] as? [String: Any])
        XCTAssertEqual(dayPlan["focus"] as? String, "Technik und Test")
        let sessions = try XCTUnwrap(dayPlan["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0]["sport"] as? String, "swim")
        XCTAssertEqual(sessions[0]["session_type"] as? String, "technique")
        XCTAssertEqual(sessions[0]["intensity"] as? String, "easy")
        XCTAssertEqual(sessions[0]["amount"] as? Double, 500)
        XCTAssertEqual(sessions[0]["focus"] as? String, "Lange Züge")
        XCTAssertNil(sessions[0]["test_id"])
        XCTAssertEqual(sessions[1]["session_type"] as? String, "test")
        XCTAssertEqual(sessions[1]["test_id"] as? String, "threshold_30min")
    }

    func testMinimalDayPlanRequestSendsOnlyVersionAndSnapshot() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-today-response.json"))

        // Leerer Wunsch, kein Training, keine Vorgabe: nichts davon geht mit.
        _ = try await makeClient(transport).fetchDayPlanV2(DayPlanV2Request(snapshot: TestFixtures.snapshot, wishes: "   "))

        let body = try Self.body(transport.requests.first)
        XCTAssertEqual(Set(body.keys), ["plan_version", "snapshot"])
    }

    func testDayPlanWithoutFocusAndEmptyEquipmentSendsAnEmptyList() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-today-response.json"))
        let request = DayPlanV2Request(snapshot: TestFixtures.snapshot, dayPlan: DayTargetV2(focus: nil, sessions: []), equipment: [])

        _ = try await makeClient(transport).fetchDayPlanV2(request)

        let body = try Self.body(transport.requests.first)
        XCTAssertEqual(body["equipment"] as? [String], [])
        let dayPlan = try XCTUnwrap(body["day_plan"] as? [String: Any])
        XCTAssertNil(dayPlan["focus"])
        XCTAssertEqual((dayPlan["sessions"] as? [Any])?.count, 0)
        XCTAssertNil(body["regenerate"])
    }

    func testDayPlanFallbackAnswerDecodes() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-today-fallback-response.json"))

        let response = try await makeClient(transport).fetchDayPlanV2(DayPlanV2Request(snapshot: TestFixtures.snapshot))

        XCTAssertEqual(response.source, .fallback)
        XCTAssertTrue(response.stale)
        XCTAssertEqual(response.fallbackReason, "timeout")
    }

    // MARK: - Sieben Tage

    func testWeekPlanSendsAtMostThreeMacroWeeksAndTheRest() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-week-response.json"))
        let starts = ["2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19"]
        let weeks = starts.map { start in Self.macroWeek(start) }
        let request = WeekPlanV2Request(
            snapshot: TestFixtures.snapshot,
            fromDate: "2026-09-30",
            today: "2026-09-30",
            unavailableDates: ["2026-10-02"],
            recentTraining: [RecentTrainingEntry(date: "2026-09-29", sport: .swim, minutes: 40, meters: 2000, hard: false)],
            macroWeeks: weeks,
            wishes: "  Freitag habe ich viel Zeit ",
            equipment: ["kickboard"],
            testSettings: .standard
        )

        let response = try await makeClient(transport).fetchWeekPlanV2(request)

        XCTAssertEqual(response.plan.days.count, 7)
        XCTAssertEqual(response.fromDate, "2026-09-30")
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.test/v1/plan/week")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
        XCTAssertEqual(sent.timeoutInterval, PlanAPIClient.planTimeout)

        let body = try Self.body(sent)
        XCTAssertEqual(body["plan_version"] as? Int, 2)
        XCTAssertEqual(body["from_date"] as? String, "2026-09-30")
        XCTAssertEqual(body["today"] as? String, "2026-09-30")
        XCTAssertEqual(body["unavailable_dates"] as? [String], ["2026-10-02"])
        XCTAssertEqual(body["wishes"] as? String, "Freitag habe ich viel Zeit")
        XCTAssertEqual(body["equipment"] as? [String], ["kickboard"])
        XCTAssertNotNil(body["snapshot"] as? [String: Any])
        XCTAssertNil(body["week_start"])

        let training = try XCTUnwrap(body["recent_training"] as? [[String: Any]])
        XCTAssertEqual(training.compactMap { $0["sport"] as? String }, ["swim"])

        let testSettings = try XCTUnwrap(body["test_settings"] as? [String: Any])
        XCTAssertEqual(testSettings["offer"] as? Bool, true)
        XCTAssertEqual(testSettings["interval_weeks"] as? Int, 6)
        XCTAssertEqual((testSettings["preferred"] as? [Any])?.count, 0)

        // Höchstens drei Wochen des Gesamtplans, die ersten.
        let sentWeeks = try XCTUnwrap(body["macro_weeks"] as? [[String: Any]])
        XCTAssertEqual(sentWeeks.compactMap { $0["week_start"] as? String }, ["2026-09-28", "2026-10-05", "2026-10-12"])
        let first = sentWeeks[0]
        XCTAssertEqual(first["phase"] as? String, "specific")
        XCTAssertEqual(first["deload"] as? Bool, false)
        XCTAssertEqual(first["focus"] as? String, "Wettkampfnah")
        XCTAssertEqual(first["total_minutes"] as? Double, 210)
        XCTAssertEqual(first["load"] as? Double, 190)
        let volumes = try XCTUnwrap(first["sports"] as? [[String: Any]])
        XCTAssertEqual(volumes.first?["sport"] as? String, "swim")
        XCTAssertEqual(volumes.first?["unit"] as? String, "meters")
        XCTAssertEqual(volumes.first?["amount"] as? Double, 3500)
        XCTAssertEqual(volumes.first?["distance_meters"] as? Double, 3500)
        XCTAssertEqual(volumes.first?["sessions"] as? Int, 2)
        let tests = try XCTUnwrap(first["tests"] as? [[String: Any]])
        XCTAssertEqual(tests.first?["sport"] as? String, "bike")
        XCTAssertEqual(tests.first?["test_id"] as? String, "threshold_30min")
        XCTAssertEqual(tests.first?["display_name"] as? String, "30-Minuten-Test")
    }

    func testWeekPlanWithoutMacroWeeksStillSendsTheLists() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-week-response.json"))

        _ = try await makeClient(transport).fetchWeekPlanV2(WeekPlanV2Request(snapshot: TestFixtures.snapshot, fromDate: "2026-09-30", today: "2026-09-30", wishes: " "))

        let body = try Self.body(transport.requests.first)
        XCTAssertEqual(Set(body.keys), ["plan_version", "snapshot", "from_date", "today", "unavailable_dates", "recent_training"])
        XCTAssertEqual(body["unavailable_dates"] as? [String], [])
        XCTAssertEqual((body["recent_training"] as? [Any])?.count, 0)
    }

    // MARK: - Gesamtplan

    func testMacroPlanRequestAndResponse() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-macro-response.json"))
        let settings = TestSettings(offer: false, intervalWeeks: 10)

        let response = try await makeClient(transport).fetchMacroPlanV2(MacroPlanV2Request(snapshot: TestFixtures.snapshot, today: "2026-09-30", testSettings: settings))

        XCTAssertEqual(response.goalDay, "2026-11-08")
        XCTAssertEqual(response.plan.weeks.count, 6)
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.test/v1/plan/macro")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.timeoutInterval, PlanAPIClient.macroTimeout)
        let body = try Self.body(sent)
        XCTAssertEqual(Set(body.keys), ["plan_version", "snapshot", "today", "test_settings"])
        XCTAssertEqual(body["plan_version"] as? Int, 2)
        XCTAssertEqual(body["today"] as? String, "2026-09-30")
        let testSettings = try XCTUnwrap(body["test_settings"] as? [String: Any])
        XCTAssertEqual(testSettings["offer"] as? Bool, false)
        XCTAssertEqual(testSettings["interval_weeks"] as? Int, 10)
    }

    func testMacroPlanWithoutTestSettingsSendsNone() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-macro-response.json"))

        _ = try await makeClient(transport).fetchMacroPlanV2(MacroPlanV2Request(snapshot: TestFixtures.snapshot, today: "2026-09-30"))

        let body = try Self.body(transport.requests.first)
        XCTAssertEqual(Set(body.keys), ["plan_version", "snapshot", "today"])
    }

    func testReviseSendsTrimmedFeedbackThePlanAndTheLastFiveRounds() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-revise-response.json"))
        let rounds = (1...7).map { (index: Int) -> MacroFeedbackRound in
            MacroFeedbackRound(feedback: "Runde \(index)", changes: ["Änderung \(index)"], adjustments: ["Korrektur \(index)"], revisedAt: TestFixtures.now)
        }
        let request = MacroRevisionRequest(
            snapshot: TestFixtures.snapshot,
            today: "2026-09-30",
            plan: Self.macroPlan(rounds: rounds),
            feedback: "  Mehr Laufen bitte, dafür weniger Schwimmen. \n",
            testSettings: .standard
        )

        let response = try await makeClient(transport).reviseMacroPlan(request)

        XCTAssertEqual(response.changes, ["Laufen in den ersten zwei Wochen 5 Minuten mehr", "Schwimmen dort um 300 m weniger"])
        XCTAssertEqual(response.feedback, "Mehr Laufen bitte, dafür weniger Schwimmen.")
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.test/v1/plan/macro/revise")
        XCTAssertEqual(sent.timeoutInterval, PlanAPIClient.macroTimeout)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")

        let body = try Self.body(sent)
        XCTAssertEqual(Set(body.keys), ["plan_version", "snapshot", "today", "plan", "feedback", "history", "test_settings"])
        XCTAssertEqual(body["plan_version"] as? Int, 2)
        XCTAssertEqual(body["today"] as? String, "2026-09-30")
        XCTAssertEqual(body["feedback"] as? String, "Mehr Laufen bitte, dafür weniger Schwimmen.")

        // Vom Plan gehen nur Begründung und Wochen mit, nicht Zielschlüssel oder Runden.
        let plan = try XCTUnwrap(body["plan"] as? [String: Any])
        XCTAssertEqual(Set(plan.keys), ["rationale", "weeks"])
        XCTAssertEqual(plan["rationale"] as? String, "Sechs Wochen bis zum Ziel.")
        let weeks = try XCTUnwrap(plan["weeks"] as? [[String: Any]])
        XCTAssertEqual(weeks.compactMap { $0["week_start"] as? String }, ["2026-09-28", "2026-10-05"])

        // Nur die letzten fünf Runden, je Feedback und Änderungen.
        let history = try XCTUnwrap(body["history"] as? [[String: Any]])
        XCTAssertEqual(history.compactMap { $0["feedback"] as? String }, ["Runde 3", "Runde 4", "Runde 5", "Runde 6", "Runde 7"])
        let firstRound = try XCTUnwrap(history.first)
        XCTAssertEqual(firstRound["changes"] as? [String], ["Änderung 3"])
        XCTAssertEqual(Set(firstRound.keys), ["feedback", "changes"])
    }

    func testReviewSendsPlanFromTheLookbackActualReasonPauseAndFeedback() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-review-response.json"))
        let actual = (1...14).map { index in
            MacroActualWeek(weekStart: "w\(index)", sports: [.init(sport: .swim, amount: 2_400, sessions: 40)])
        }
        let request = MacroReviewRequest(
            snapshot: TestFixtures.snapshot,
            today: "2026-09-30",
            plan: Self.macroPlan(),
            planFrom: "2026-10-05",
            actual: actual,
            reason: .pause,
            pause: PauseReport(kind: .sick, from: "2026-09-20", to: nil, reportedAt: TestFixtures.now),
            feedback: "  Knie zwickt \n"
        )

        let response = try await makeClient(transport).reviewMacroPlan(request)

        XCTAssertEqual(response.summary, "Schwimmen 96 % erfüllt, Radfahren 88 %, Laufen 70 %. In der zweiten Woche fielen zwei Läufe aus.")
        XCTAssertEqual(response.reason, .scheduled)
        XCTAssertEqual(response.changes?.count, 2)
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.test/v1/plan/macro/review")
        XCTAssertEqual(sent.timeoutInterval, PlanAPIClient.macroTimeout)

        let body = try Self.body(sent)
        XCTAssertEqual(Set(body.keys), ["plan_version", "snapshot", "today", "plan", "actual", "reason", "pause", "feedback"])
        XCTAssertEqual(body["reason"] as? String, "pause")
        XCTAssertEqual(body["feedback"] as? String, "Knie zwickt")
        XCTAssertEqual(body["pause"] as? [String: String], ["from": "2026-09-20", "kind": "sick"])
        let plan = try XCTUnwrap(body["plan"] as? [String: Any])
        XCTAssertEqual((plan["weeks"] as? [[String: Any]])?.compactMap { $0["week_start"] as? String }, ["2026-10-05"])
        let sentActual = try XCTUnwrap(body["actual"] as? [[String: Any]])
        XCTAssertEqual(sentActual.count, 12)
        XCTAssertEqual(sentActual.first?["week_start"] as? String, "w3")
        let sport = try XCTUnwrap((sentActual.first?["sports"] as? [[String: Any]])?.first)
        XCTAssertEqual(sport["sessions"] as? Int, 30)
        XCTAssertEqual(sport["amount"] as? Double, 2_400)
    }

    func testReviewWithoutPauseAndWithBlankFeedbackLeavesThemOut() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-review-response.json"))
        let request = MacroReviewRequest(
            snapshot: TestFixtures.snapshot, today: "2026-09-30", plan: Self.macroPlan(), planFrom: "2026-09-28", actual: [], reason: .lowCompliance, feedback: "   "
        )

        _ = try await makeClient(transport).reviewMacroPlan(request)

        let body = try Self.body(transport.requests.first)
        XCTAssertEqual(Set(body.keys), ["plan_version", "snapshot", "today", "plan", "actual", "reason"])
        XCTAssertEqual(body["reason"] as? String, "low_compliance")
    }

    func testReviewSendsNewPerformanceValuesWithTheirPreviousOnes() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-review-response.json"))
        let change = PerformanceChange(
            sport: .swim, metric: "css_pace_per_100m", previous: 110, value: 104, source: .tested, measuredAt: TestFixtures.date(daysAgo: 2, hour: 8)
        )
        let request = MacroReviewRequest(
            snapshot: TestFixtures.snapshot, today: "2026-09-30", plan: Self.macroPlan(), planFrom: "2026-09-28", actual: [], reason: .scheduled,
            performanceChanges: [change]
        )

        _ = try await makeClient(transport).reviewMacroPlan(request)

        let body = try Self.body(transport.requests.first)
        let changes = try XCTUnwrap(body["performance_changes"] as? [[String: Any]])
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0]["sport"] as? String, "swim")
        XCTAssertEqual(changes[0]["metric"] as? String, "css_pace_per_100m")
        XCTAssertEqual(changes[0]["previous"] as? Double, 110)
        XCTAssertEqual(changes[0]["value"] as? Double, 104)
        XCTAssertEqual(changes[0]["source"] as? String, "tested")
        XCTAssertEqual(changes[0]["measured_at"] as? String, "2026-09-28T08:00:00Z")
    }

    func testReviseCutsOverlongTexts() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-revise-response.json"))
        let round = MacroFeedbackRound(
            feedback: String(repeating: "r", count: MacroRevisionRequest.maxFeedbackLength + 100),
            changes: Array(repeating: String(repeating: "c", count: 350), count: 10),
            revisedAt: TestFixtures.now
        )
        let request = MacroRevisionRequest(
            snapshot: TestFixtures.snapshot,
            today: "2026-09-30",
            plan: Self.macroPlan(rounds: [round], rationale: String(repeating: "b", count: 2100)),
            feedback: "  " + String(repeating: "f", count: MacroRevisionRequest.maxFeedbackLength + 20) + "  "
        )

        _ = try await makeClient(transport).reviseMacroPlan(request)

        let body = try Self.body(transport.requests.first)
        XCTAssertEqual(body["feedback"] as? String, String(repeating: "f", count: 1000))
        let plan = try XCTUnwrap(body["plan"] as? [String: Any])
        XCTAssertEqual((plan["rationale"] as? String)?.count, 2000)
        let history = try XCTUnwrap(body["history"] as? [[String: Any]])
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual((history.first?["feedback"] as? String)?.count, 1000)
        let changes = try XCTUnwrap(history.first?["changes"] as? [String])
        XCTAssertEqual(changes.count, 8)
        XCTAssertEqual(changes.map(\.count), Array(repeating: 300, count: 8))
        XCTAssertNil(body["test_settings"])
    }

    func testReviseWithoutEarlierRoundsSendsNoHistory() async throws {
        let transport = StubTransport(status: 200, body: try Self.contract("plan-v2-revise-response.json"))
        let request = MacroRevisionRequest(snapshot: TestFixtures.snapshot, today: "2026-09-30", plan: Self.macroPlan(), feedback: "Mehr Laufen")

        _ = try await makeClient(transport).reviseMacroPlan(request)

        let body = try Self.body(transport.requests.first)
        XCTAssertNil(body["history"])
        XCTAssertEqual(body["feedback"] as? String, "Mehr Laufen")
    }

    func testEmptyFeedbackIsRejectedWithoutARequest() async {
        let transport = StubTransport(status: 200, body: "{}")
        let client = makeClient(transport)
        let request = MacroRevisionRequest(snapshot: TestFixtures.snapshot, today: "2026-09-30", plan: Self.macroPlan(), feedback: " \n\t ")

        let error = await Self.failure { try await client.reviseMacroPlan(request) }

        XCTAssertEqual(error as? PlanAPIError, .invalidRequest(details: ["feedback: leer"]))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: - Antworten des Servers

    func testPlanV1AnswerMeansTheServerIsOutdated() async throws {
        // Ein Server ohne Plan v2 antwortet auf dieselbe Route mit einem Plan v1 (ohne `plan_version`).
        let withoutVersion = await dayFailure(status: 200, body: TestFixtures.responseJSON)
        let olderVersion = await dayFailure(status: 200, body: #"{"plan_version": 1}"#)
        // Die Antwort eines alten Servers: ein Gesamtplan ohne `plan_version`.
        let oldMacroBody = #"{"goal_day":"2027-07-04","generated_at":"2026-09-30T10:00:00.000Z","plan":{"rationale":"alt","weeks":[]},"adjustments":[]}"#
        let client = makeClient(StubTransport(status: 200, body: oldMacroBody))
        let macro = await Self.failure { try await client.fetchMacroPlanV2(MacroPlanV2Request(snapshot: TestFixtures.snapshot, today: "2026-09-30")) }

        XCTAssertEqual(withoutVersion as? PlanAPIError, .serverOutdated)
        XCTAssertEqual(olderVersion as? PlanAPIError, .serverOutdated)
        XCTAssertEqual(macro as? PlanAPIError, .serverOutdated)
    }

    func testUnknownRouteMeansTheServerIsOutdatedForEveryRequest() async {
        let transport = StubTransport(status: 404, body: #"{"error":"not_found"}"#)
        let client = makeClient(transport)
        let dayRequest = DayPlanV2Request(snapshot: TestFixtures.snapshot)
        let weekRequest = WeekPlanV2Request(snapshot: TestFixtures.snapshot, fromDate: "2026-09-30", today: "2026-09-30")
        let macroRequest = MacroPlanV2Request(snapshot: TestFixtures.snapshot, today: "2026-09-30")
        let reviseRequest = MacroRevisionRequest(snapshot: TestFixtures.snapshot, today: "2026-09-30", plan: Self.macroPlan(), feedback: "Mehr Laufen")

        let day = await Self.failure { try await client.fetchDayPlanV2(dayRequest) }
        let week = await Self.failure { try await client.fetchWeekPlanV2(weekRequest) }
        let macro = await Self.failure { try await client.fetchMacroPlanV2(macroRequest) }
        let revise = await Self.failure { try await client.reviseMacroPlan(reviseRequest) }

        XCTAssertEqual(day as? PlanAPIError, .serverOutdated)
        XCTAssertEqual(week as? PlanAPIError, .serverOutdated)
        XCTAssertEqual(macro as? PlanAPIError, .serverOutdated)
        XCTAssertEqual(revise as? PlanAPIError, .serverOutdated)
        XCTAssertEqual(transport.requests.compactMap { $0.url?.absoluteString }, [
            "https://example.test/v1/plan/today",
            "https://example.test/v1/plan/week",
            "https://example.test/v1/plan/macro",
            "https://example.test/v1/plan/macro/revise"
        ])
    }

    func testRejectedRequestCarriesTheDetails() async {
        let invalid = await dayFailure(
            status: 400,
            body: #"{"error":"invalid_request","details":[{"path":"test_settings.interval_weeks","message":"Too big"},{"path":"day_plan","message":"Invalid"}]}"#
        )
        let withoutDetails = await dayFailure(status: 400, body: "kaputt")

        XCTAssertEqual(invalid as? PlanAPIError, .invalidRequest(details: ["test_settings.interval_weeks: Too big", "day_plan: Invalid"]))
        XCTAssertEqual(withoutDetails as? PlanAPIError, .invalidRequest(details: []))
    }

    func testUnavailablePlanCarriesTheReason() async {
        let withReason = await dayFailure(status: 503, body: #"{"error":"plan_unavailable","reason":"timeout"}"#)
        let withoutReason = await dayFailure(status: 503, body: "")

        XCTAssertEqual(withReason as? PlanAPIError, .planUnavailable(reason: "timeout"))
        XCTAssertEqual(withoutReason as? PlanAPIError, .planUnavailable(reason: nil))
    }

    func testAnswerThatIsNoJSONObjectIsInvalid() async {
        let array = await dayFailure(status: 200, body: "[1, 2]")
        let html = await dayFailure(status: 200, body: "<html>")

        XCTAssertEqual(array as? PlanAPIError, .invalidResponse("kein JSON-Objekt"))
        XCTAssertEqual(html as? PlanAPIError, .invalidResponse("kein JSON-Objekt"))
    }

    func testVersionTwoAnswerWithMissingFieldsIsInvalid() async {
        let error = await dayFailure(status: 200, body: #"{"plan_version": 2, "source": "claude"}"#)

        XCTAssertTrue(Self.isInvalidResponse(error), "erwartet: unverständliche Antwort, bekam \(String(describing: error))")
    }

    func testOtherStatusesAndNetworkFailures() async {
        let unauthorized = await dayFailure(status: 401, body: "{}")
        let server = await dayFailure(status: 500, body: "{}")
        let client = makeClient(StubTransport(error: URLError(.notConnectedToInternet)))
        let request = DayPlanV2Request(snapshot: TestFixtures.snapshot)
        let offline = await Self.failure { try await client.fetchDayPlanV2(request) }

        XCTAssertEqual(unauthorized as? PlanAPIError, .unauthorized)
        XCTAssertEqual(server as? PlanAPIError, .server(status: 500))
        XCTAssertEqual(offline as? PlanAPIError, .network(PlanAPIClient.describe(URLError(.notConnectedToInternet))))
    }
}

// MARK: - Testeinstellungen

final class PlanV2TestSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "PlanV2TestSettingsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testIntervalIsClampedToTheServerRange() {
        XCTAssertEqual(TestSettings.intervalRange, 4...12)
        XCTAssertEqual(TestSettings(offer: true, intervalWeeks: 1).intervalWeeks, 4)
        XCTAssertEqual(TestSettings(offer: true, intervalWeeks: 4).intervalWeeks, 4)
        XCTAssertEqual(TestSettings(offer: true, intervalWeeks: 7).intervalWeeks, 7)
        XCTAssertEqual(TestSettings(offer: true, intervalWeeks: 12).intervalWeeks, 12)
        XCTAssertEqual(TestSettings(offer: false, intervalWeeks: 52).intervalWeeks, 12)
        XCTAssertEqual(TestSettings(offer: true, intervalWeeks: -3).intervalWeeks, 4)
    }

    func testStandardOffersTestsEverySixWeeks() {
        XCTAssertEqual(TestSettings.standard, TestSettings(offer: true, intervalWeeks: 6, preferred: []))
        XCTAssertTrue(TestSettings.standard.offer)
        XCTAssertEqual(TestSettings.standard.intervalWeeks, 6)
        XCTAssertEqual(TestSettings.standard.preferred, [])
    }

    func testPreferredTestPerSport() {
        let settings = TestSettings.standard
            .preferring("threshold_30min", for: .bike)
            .preferring("css_400_200", for: .swim)

        XCTAssertEqual(settings.preferredTest(for: .bike), "threshold_30min")
        XCTAssertEqual(settings.preferredTest(for: .swim), "css_400_200")
        XCTAssertNil(settings.preferredTest(for: .run))

        // Ersetzen statt doppelt eintragen; `nil` nimmt die Vorliebe zurück.
        let changed = settings.preferring("time_trial_1000m", for: .swim).preferring(nil, for: .bike)

        XCTAssertEqual(changed.preferred, [TestSettings.Preference(sport: .swim, testID: "time_trial_1000m")])
        XCTAssertNil(changed.preferredTest(for: .bike))
        XCTAssertEqual(changed.offer, settings.offer)
        XCTAssertEqual(changed.intervalWeeks, settings.intervalWeeks)
        // Das Original bleibt, wie es war.
        XCTAssertEqual(settings.preferred.count, 2)
        XCTAssertEqual(TestSettings.standard.preferring(nil, for: .run), .standard)
    }

    func testWithoutAnythingStoredTheStandardApplies() {
        XCTAssertEqual(UserDefaultsTestSettingsStore(defaults: defaults).settings(), .standard)
    }

    func testSavedSettingsSurviveANewStore() {
        let settings = TestSettings(offer: false, intervalWeeks: 8, preferred: [TestSettings.Preference(sport: .run, testID: "entry_easy_25min")])

        UserDefaultsTestSettingsStore(defaults: defaults).save(settings)

        XCTAssertEqual(UserDefaultsTestSettingsStore(defaults: defaults).settings(), settings)
        XCTAssertNotNil(defaults.data(forKey: UserDefaultsTestSettingsStore.storageKey))
    }

    func testStoredIntervalOutsideTheRangeIsClampedOnLoad() {
        let store = UserDefaultsTestSettingsStore(defaults: defaults)
        var settings = TestSettings.standard
        settings.intervalWeeks = 20

        store.save(settings)
        XCTAssertEqual(store.settings().intervalWeeks, 12)

        settings.intervalWeeks = 1
        store.save(settings)
        XCTAssertEqual(store.settings().intervalWeeks, 4)
    }

    func testCorruptDataFallsBackToTheStandard() {
        defaults.set(Data("kaputt".utf8), forKey: UserDefaultsTestSettingsStore.storageKey)

        XCTAssertEqual(UserDefaultsTestSettingsStore(defaults: defaults).settings(), .standard)
    }
}

// MARK: - Bisheriges Training

final class PlanV2RecentTrainingTests: XCTestCase {
    private func entries(
        _ workouts: [Workout],
        from start: String = "2026-09-24",
        before end: String = "2026-09-30",
        plannedHard: (String, SportID) -> Bool = { _, _ in false },
        maximumHeartRate: Double? = nil
    ) -> [RecentTrainingEntry] {
        RecentTraining.entries(
            workouts: workouts,
            from: start,
            before: end,
            plannedHard: plannedHard,
            maximumHeartRate: maximumHeartRate,
            calendar: TestFixtures.utc
        )
    }

    private static func day(_ daysAgo: Int) -> String {
        PlanFormatting.isoDay(TestFixtures.date(daysAgo: daysAgo, hour: 8), calendar: TestFixtures.utc)
    }

    func testOnlyWorkoutsInsideTheWindowCount() {
        let workouts = [
            TestFixtures.workout(.swim, daysAgo: 0, minutes: 30),
            TestFixtures.workout(.run, daysAgo: 1, minutes: 30),
            TestFixtures.workout(.bike, daysAgo: 6, minutes: 30),
            TestFixtures.workout(.run, daysAgo: 7, minutes: 30)
        ]

        let result = entries(workouts)

        // Beginn eingeschlossen, Ende nicht.
        XCTAssertEqual(result.map(\.date), ["2026-09-24", "2026-09-29"])
        XCTAssertEqual(result.map(\.sport), [.bike, .run])
        XCTAssertEqual(entries([]), [])
    }

    func testUnknownSportsAreDropped() {
        let workouts = [
            TestFixtures.workout("kayak", daysAgo: 2, minutes: 60),
            TestFixtures.workout(.swim, daysAgo: 3, minutes: 30, meters: 1500)
        ]

        XCTAssertEqual(entries(workouts).map(\.sport), [.swim])
    }

    func testHardComesFromThePlanOrTheHeartRate() {
        let workouts = [
            TestFixtures.workout(.bike, daysAgo: 2, minutes: 60, heartRate: 120),
            TestFixtures.workout(.run, daysAgo: 3, minutes: 40, heartRate: 120),
            TestFixtures.workout(.run, daysAgo: 4, minutes: 40, heartRate: 168),
            TestFixtures.workout(.swim, daysAgo: 5, minutes: 30, heartRate: 167),
            TestFixtures.workout(.bike, daysAgo: 6, minutes: 30)
        ]
        // Hart geplant war Rad am 27. und 28.09.; am 27. wurde aber gelaufen.
        let plannedHard: (String, SportID) -> Bool = { date, sport in
            sport == .bike && (date == "2026-09-27" || date == "2026-09-28")
        }

        let withHeartRate = entries(workouts, plannedHard: plannedHard, maximumHeartRate: 190)
        let withoutHeartRate = entries(workouts, plannedHard: plannedHard)

        XCTAssertEqual(withHeartRate.map(\.date), ["2026-09-24", "2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28"])
        // 168 liegt über 88 % von 190 (167,2), 167 darunter.
        XCTAssertEqual(withHeartRate.map(\.hard), [false, false, true, false, true])
        // Ohne Maximalpuls zählt nur der Plan.
        XCTAssertEqual(withoutHeartRate.map(\.hard), [false, false, false, false, true])
    }

    func testMinutesAndMetersAreRoundedAndClamped() {
        let start = TestFixtures.date(daysAgo: 4, hour: 8)
        let broken = Workout(id: UUID(), sport: .run, startDate: start, endDate: start, duration: -60, distanceMeters: -5)
        let workouts = [
            TestFixtures.workout(.swim, daysAgo: 1, minutes: 45.4, meters: 1234.6),
            TestFixtures.workout(.run, daysAgo: 2, minutes: 2000),
            TestFixtures.workout(.bike, daysAgo: 3, minutes: 30, meters: 2_000_000),
            broken
        ]

        XCTAssertEqual(entries(workouts), [
            RecentTrainingEntry(date: "2026-09-26", sport: .run, minutes: 0, meters: 0, hard: false),
            RecentTrainingEntry(date: "2026-09-27", sport: .bike, minutes: 30, meters: 1_000_000, hard: false),
            RecentTrainingEntry(date: "2026-09-28", sport: .run, minutes: 1440, meters: 0, hard: false),
            RecentTrainingEntry(date: "2026-09-29", sport: .swim, minutes: 45, meters: 1235, hard: false)
        ])
    }

    func testOnlyTheNewestFortyAreKeptOldestFirst() {
        // Neueste zuerst übergeben, damit die Sortierung etwas zu tun hat.
        let workouts = (1...45).map { (daysAgo: Int) -> Workout in
            TestFixtures.workout(.run, daysAgo: daysAgo, minutes: 30)
        }

        let result = entries(workouts, from: "2026-08-01", before: "2026-09-30")

        XCTAssertEqual(RecentTraining.maximumEntries, 40)
        XCTAssertEqual(result.count, 40)
        XCTAssertEqual(result.first?.date, Self.day(40))
        XCTAssertEqual(result.last?.date, Self.day(1))
        XCTAssertEqual(result.map(\.date), result.map(\.date).sorted())
    }
}
