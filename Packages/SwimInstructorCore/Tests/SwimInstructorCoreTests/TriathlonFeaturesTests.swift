import XCTest
@testable import SwimInstructorCore

/// Koppeltraining, drinnen, Kraft und Mobilität, Kalender, Wetter und der Wettkampftag: Modelle, Anfragen, Anzeige.
final class TriathlonFeaturesTests: XCTestCase {
    private static func contract<T: Decodable>(_ type: T.Type, _ file: String) throws -> T {
        try PlanCoding.jsonDecoder().decode(type, from: RepoPaths.contractData("wire/\(file)"))
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try PlanCoding.jsonDecoder().decode(type, from: Data(json.utf8))
    }

    private static func body(_ request: URLRequest?) throws -> [String: Any] {
        let data = try XCTUnwrap(request?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let configuration = BackendConfiguration(baseURL: URL(string: "https://example.test")!, token: "geheim")

    // MARK: - Tagesplan

    func testTodayResponseCarriesBrickIndoorAndExtrasWithExercises() throws {
        let response = try Self.contract(DayPlanV2Response.self, "plan-v2-today-response.json")

        XCTAssertEqual(response.plan.sessions.map(\.brick), [false, false])
        XCTAssertEqual(response.plan.sessions.map(\.indoor), [false, false])
        let extra = try XCTUnwrap(response.plan.extras.first)
        XCTAssertEqual(extra.kind, .mobility)
        XCTAssertEqual(extra.minutes, 10)
        XCTAssertEqual(extra.exercises.map(\.name), ["Hüftbeuger-Dehnung", "Wadenheben"])
        XCTAssertEqual(extra.exercises.map(\.summary), ["2 × 30 s", "2 × 15"])
        XCTAssertEqual(extra.exercises[1].restSeconds, 30)
    }

    func testOlderPlansWithoutTheNewFieldsStillDecode() throws {
        let session = try Self.decode(DaySession.self, #"{"sport":"run","session_type":"endurance","intensity":"easy","focus":"x","test":null,"amount":30,"unit":"minutes","distance_meters":5000,"duration_minutes":30,"steps":[]}"#)
        let plan = try Self.decode(DayPlanV2.self, #"{"rationale":"r","sessions":[],"coach_notes":[]}"#)
        let week = try Self.decode(WeekSession.self, #"{"sport":"bike","session_type":"endurance","intensity":"easy","amount":60,"unit":"minutes","minutes":60,"distance_meters":25000,"focus":"x","test":null}"#)

        XCTAssertFalse(session.brick)
        XCTAssertFalse(session.indoor)
        XCTAssertEqual(plan.extras, [])
        XCTAssertFalse(week.brick)
        XCTAssertFalse(week.indoor)
    }

    func testUnknownExtraKindsAreDropped() throws {
        let plan = try Self.decode(DayPlanV2.self, #"{"rationale":"r","sessions":[],"extras":[{"kind":"yoga","minutes":20,"focus":"x","exercises":[]},{"kind":"strength","minutes":30,"focus":"Rumpf","exercises":[{"name":"Plank","sets":3,"seconds":40}]}],"coach_notes":[]}"#)

        XCTAssertEqual(plan.extras.map(\.kind), [.strength])
        XCTAssertEqual(plan.extras.first?.exercises.first?.restSeconds, 0)
        XCTAssertEqual(plan.extras.first?.exercises.first?.summary, "3 × 40 s")
    }

    // MARK: - Sieben Tage

    func testWeekResponseCarriesExtrasPerDayAndIndoor() throws {
        let response = try Self.contract(WeekPlanV2Response.self, "plan-v2-week-response.json")
        let days = response.plan.days

        XCTAssertEqual(days.map { $0.extras.map(\.kind) }, [[], [.mobility], [], [.strength], [], [], []])
        XCTAssertEqual(days[4].sessions.map(\.indoor), [true])
        XCTAssertTrue(days.flatMap(\.sessions).allSatisfy { !$0.brick })
    }

    func testTheDayTargetCarriesBrickIndoorAndExtrasOnlyWhenSet() throws {
        let bike = WeekSession(sport: .bike, sessionType: .endurance, intensity: .easy, amount: 60, unit: .minutes, minutes: 60, distanceMeters: 25_000, focus: "Rad", indoor: true)
        let run = WeekSession(sport: .run, sessionType: .endurance, intensity: .easy, amount: 15, unit: .minutes, minutes: 15, distanceMeters: 2_500, focus: "Koppellauf", brick: true)
        var day = PlannedDay(date: "2026-09-30", content: PlannedDayContent(focus: "Koppeltraining", sessions: [bike, run]), extras: [WeekExtra(kind: .mobility, minutes: 10, focus: "Hüfte")])

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: PlanCoding.jsonEncoder().encode(day.target)) as? [String: Any])
        let sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessions[0]["indoor"] as? Bool, true)
        XCTAssertNil(sessions[0]["brick"])
        XCTAssertEqual(sessions[1]["brick"] as? Bool, true)
        XCTAssertNil(sessions[1]["indoor"])
        XCTAssertEqual((json["extras"] as? [[String: Any]])?.first?["kind"] as? String, "mobility")

        // Ohne Zeit: Ruhetag ohne Ergänzung.
        day.isUnavailable = true
        XCTAssertEqual(day.target, DayTargetV2(focus: "Koppeltraining", sessions: []))
        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: PlanCoding.jsonEncoder().encode(day.target)) as? [String: Any])
        XCTAssertNil(empty["extras"])
    }

    // MARK: - Einstellungen

    func testSupplementsAndPreferencesStayInRange() {
        XCTAssertEqual(Supplements(strengthPerWeek: 9, mobilityPerWeek: -1), Supplements(strengthPerWeek: 3, mobilityPerWeek: 0))
        XCTAssertTrue(Supplements.none.isEmpty)
        XCTAssertEqual(Supplements(strengthPerWeek: 2, mobilityPerWeek: 4).perWeek(.mobility), 4)

        let preferences = PlanningPreferences(supplements: .none, usesWeather: true, usesCalendar: true, calendarStartHour: 22, calendarEndHour: 5)
        XCTAssertEqual(preferences.calendarStartHour, 22)
        XCTAssertEqual(preferences.calendarEndHour, 23)
    }

    func testPreferencesSurviveARestart() {
        let suite = "TriathlonFeaturesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPlanningPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.preferences(), .standard)

        let changed = PlanningPreferences(supplements: Supplements(strengthPerWeek: 2, mobilityPerWeek: 3), usesWeather: true, usesCalendar: false, calendarStartHour: 7, calendarEndHour: 20)
        store.save(changed)

        XCTAssertEqual(UserDefaultsPlanningPreferencesStore(defaults: defaults).preferences(), changed)
    }

    func testIndoorEquipmentComesFromTheModulesAndIsOffByDefault() {
        let suite = "TriathlonFeaturesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsIndoorEquipmentStore(defaults: defaults)

        XCTAssertEqual(SportRegistry.standard.indoorEquipment.map(\.id), ["indoor_trainer", "treadmill"])
        XCTAssertEqual(store.ownedIndoorEquipment(), [])
        store.setOwnedIndoorEquipment(["treadmill", "unbekannt"])
        XCTAssertEqual(store.ownedIndoorEquipment(), ["treadmill"])
    }

    func testTheLocationIsRoundedToAboutTenKilometers() {
        XCTAssertEqual(GeoPoint(latitude: 52.5234, longitude: 13.4114), GeoPoint(latitude: 52.5, longitude: 13.4))
        XCTAssertEqual(GeoPoint(latitude: 48.137, longitude: 11.575).longitude, 11.6, accuracy: 0.0001)
        XCTAssertEqual(GeoPoint(latitude: 95, longitude: -200), GeoPoint(latitude: 90, longitude: -180))
    }

    // MARK: - Kalender

    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        TestFixtures.utc.date(bySettingHour: hour, minute: minute, second: 0, of: TestFixtures.now)!
    }

    func testFreeMinutesAreTheLongestFreeBlockInTheWindow() {
        let busy = [
            DateInterval(start: time(5), end: time(8)),      // ragt vor das Fenster
            DateInterval(start: time(9), end: time(12)),
            DateInterval(start: time(11), end: time(13)),    // überlappt
            DateInterval(start: time(18, 30), end: time(23)) // ragt hinaus
        ]

        XCTAssertEqual(CalendarAvailability.freeMinutes(busy: busy, day: TestFixtures.now, startHour: 6, endHour: 21, calendar: TestFixtures.utc), 330)
        XCTAssertEqual(CalendarAvailability.freeMinutes(busy: [], day: TestFixtures.now, startHour: 6, endHour: 21, calendar: TestFixtures.utc), 900)
        XCTAssertEqual(CalendarAvailability.freeMinutes(busy: [DateInterval(start: time(0), end: time(23, 59))], day: TestFixtures.now, startHour: 6, endHour: 21, calendar: TestFixtures.utc), 0)
        XCTAssertEqual(CalendarAvailability.freeMinutes(busy: [], day: TestFixtures.now, startHour: 21, endHour: 6, calendar: TestFixtures.utc), 0)
    }

    func testPlanningExtrasFindTheMinutesOfADay() {
        let extras = PlanningExtras(availability: [DayAvailability(date: "2026-09-30", minutes: 45), DayAvailability(date: "2026-10-01", minutes: -5)])
        XCTAssertEqual(extras.availableMinutes(on: "2026-09-30"), 45)
        XCTAssertEqual(extras.availableMinutes(on: "2026-10-01"), 0)
        XCTAssertNil(extras.availableMinutes(on: "2026-10-02"))
    }

    // MARK: - Anfragen

    func testTheWeekRequestSendsMissedSessionsReasonSupplementsLocationAndAvailability() async throws {
        let transport = StubTransport(status: 200, body: String(decoding: try RepoPaths.contractData("wire/plan-v2-week-response.json"), as: UTF8.self))
        let request = WeekPlanV2Request(
            snapshot: TestFixtures.snapshot,
            fromDate: "2026-09-30",
            today: "2026-09-30",
            recentTraining: [RecentTrainingEntry(date: "2026-09-29", sport: .run, minutes: 40, meters: 6_000, hard: false, effort: 9, pain: 2, painArea: .knee)],
            missedSessions: [MissedSession(date: "2026-09-29", sport: .bike, sessionType: .endurance, intensity: .easy, amount: 60)],
            reason: .pain,
            extras: PlanningExtras(
                supplements: Supplements(strengthPerWeek: 2, mobilityPerWeek: 1),
                location: GeoPoint(latitude: 52.52, longitude: 13.41),
                availability: [DayAvailability(date: "2026-10-01", minutes: 45)]
            )
        )

        _ = try await PlanAPIClient(configuration: configuration, transport: transport).fetchWeekPlanV2(request)

        let body = try Self.body(transport.requests.first)
        XCTAssertEqual(body["reason"] as? String, "pain")
        let missed = try XCTUnwrap(body["missed_sessions"] as? [[String: Any]])
        XCTAssertEqual(missed.first?["sport"] as? String, "bike")
        XCTAssertEqual(missed.first?["session_type"] as? String, "endurance")
        XCTAssertEqual(missed.first?["amount"] as? Double, 60)
        let supplements = try XCTUnwrap(body["supplements"] as? [String: Any])
        XCTAssertEqual(supplements["strength_per_week"] as? Int, 2)
        XCTAssertEqual(supplements["mobility_per_week"] as? Int, 1)
        let location = try XCTUnwrap(body["location"] as? [String: Any])
        XCTAssertEqual(location["latitude"] as? Double, 52.5)
        XCTAssertEqual((body["availability"] as? [[String: Any]])?.first?["minutes"] as? Int, 45)
        let training = try XCTUnwrap((body["recent_training"] as? [[String: Any]])?.first)
        XCTAssertEqual(training["effort"] as? Double, 9)
        XCTAssertEqual(training["pain"] as? Int, 2)
        XCTAssertEqual(training["pain_area"] as? String, "knee")
    }

    func testWithoutExtrasTheWeekRequestStaysAsBefore() async throws {
        let transport = StubTransport(status: 200, body: String(decoding: try RepoPaths.contractData("wire/plan-v2-week-response.json"), as: UTF8.self))
        let request = WeekPlanV2Request(snapshot: TestFixtures.snapshot, fromDate: "2026-09-30", today: "2026-09-30", extras: PlanningExtras(supplements: .none))

        _ = try await PlanAPIClient(configuration: configuration, transport: transport).fetchWeekPlanV2(request)

        let body = try Self.body(transport.requests.first)
        for key in ["missed_sessions", "reason", "supplements", "location", "availability"] {
            XCTAssertNil(body[key], key)
        }
    }

    func testTheDayRequestSendsSupplementsLocationAndFreeMinutes() async throws {
        let transport = StubTransport(status: 200, body: String(decoding: try RepoPaths.contractData("wire/plan-v2-today-response.json"), as: UTF8.self))
        let request = DayPlanV2Request(
            snapshot: TestFixtures.snapshot,
            extras: PlanningExtras(supplements: Supplements(strengthPerWeek: 0, mobilityPerWeek: 3), location: GeoPoint(latitude: 48.1, longitude: 11.6), availability: [DayAvailability(date: "2026-09-30", minutes: 60)])
        )

        _ = try await PlanAPIClient(configuration: configuration, transport: transport).fetchDayPlanV2(request)

        let body = try Self.body(transport.requests.first)
        XCTAssertEqual((body["supplements"] as? [String: Any])?["mobility_per_week"] as? Int, 3)
        XCTAssertEqual((body["location"] as? [String: Any])?["longitude"] as? Double, 11.6)
        XCTAssertEqual(body["available_minutes"] as? Int, 60)
    }

    // MARK: - Rückmeldung und Anpassung

    private func workout(_ sport: SportID, daysAgo: Int, hour: Int = 8, minutes: Double = 45, effort: Double? = nil) -> Workout {
        let start = TestFixtures.date(daysAgo: daysAgo, hour: hour)
        return Workout(
            id: UUID(),
            sport: sport,
            startDate: start,
            endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60,
            distanceMeters: 5_000,
            metrics: effort.map { [.effort: $0] } ?? [:]
        )
    }

    private func feedback(for workout: Workout, effort: Int? = nil, pain: PainLevel = .none, area: PainArea? = nil) -> SessionFeedback {
        SessionFeedback(
            workoutID: workout.id,
            date: PlanFormatting.isoDay(workout.startDate, calendar: TestFixtures.utc),
            sport: workout.sport,
            effort: effort,
            pain: pain,
            painArea: area,
            recordedAt: TestFixtures.now
        )
    }

    func testFeedbackIsClampedAndForgetsTheAreaWithoutPain() {
        let run = workout(.run, daysAgo: 0)
        XCTAssertEqual(feedback(for: run, effort: 14).effort, 10)
        XCTAssertNil(feedback(for: run, pain: .none, area: .knee).painArea)
        XCTAssertEqual(feedback(for: run, pain: .light, area: .knee).painArea, .knee)
    }

    func testTheFeedbackStoreKeepsOneEntryPerWorkoutAndForgetsOldOnes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileSessionFeedbackStore(fileURL: url, now: { TestFixtures.now }, calendar: TestFixtures.utc)
        let run = workout(.run, daysAgo: 0)
        let old = SessionFeedback(workoutID: UUID(), date: "2026-06-01", sport: .swim, effort: 5, pain: .none, painArea: nil, recordedAt: TestFixtures.now)

        try store.save(old)
        try store.save(feedback(for: run, effort: 5))
        try store.save(feedback(for: run, effort: 8, pain: .moderate, area: .shin))

        XCTAssertEqual(store.all().map(\.workoutID), [run.id])
        XCTAssertEqual(store.all().first?.effort, 8)
        XCTAssertEqual(store.all().first?.painArea, .shin)
    }

    func testRecentTrainingCarriesEffortAndPain() {
        let rated = workout(.run, daysAgo: 1, effort: 4)
        let healthOnly = workout(.bike, daysAgo: 2, effort: 8.4)
        let entries = RecentTraining.entries(
            workouts: [rated, healthOnly],
            from: "2026-09-23",
            before: "2026-10-01",
            feedback: [feedback(for: rated, effort: 6, pain: .light, area: .achilles)],
            calendar: TestFixtures.utc
        )

        XCTAssertEqual(entries.map(\.sport), [.bike, .run])
        // Health allein: 8,4 von 10 ist hart.
        XCTAssertEqual(entries[0].effort, 8.4)
        XCTAssertNil(entries[0].pain)
        XCTAssertTrue(entries[0].hard)
        // Die eigene Angabe geht vor Health.
        XCTAssertEqual(entries[1].effort, 6)
        XCTAssertEqual(entries[1].pain, 1)
        XCTAssertEqual(entries[1].painArea, .achilles)
        XCTAssertFalse(entries[1].hard)
    }

    private func plannedWeek() -> WeekPlanV2 {
        let bike = WeekSession(sport: .bike, sessionType: .endurance, intensity: .easy, amount: 60, unit: .minutes, minutes: 60, distanceMeters: 25_000, focus: "Rad")
        let run = WeekSession(sport: .run, sessionType: .intervals, intensity: .hard, amount: 40, unit: .minutes, minutes: 40, distanceMeters: 7_000, focus: "Intervalle")
        let swim = WeekSession(sport: .swim, sessionType: .endurance, intensity: .easy, amount: 1_500, unit: .meters, minutes: 30, distanceMeters: 1_500, focus: "Locker")
        return WeekPlanV2(weekStart: "2026-09-28", generatedAt: TestFixtures.now, rationale: "Woche", days: [
            PlannedDay(date: "2026-09-28", content: PlannedDayContent(focus: "Rad", sessions: [bike])),
            PlannedDay(date: "2026-09-29", content: PlannedDayContent(focus: "Laufen und Schwimmen", sessions: [run, swim])),
            PlannedDay(date: "2026-09-30", content: PlannedDayContent(focus: "Rad", sessions: [bike]))
        ])
    }

    func testMissedSessionsArePlannedSportsWithoutAWorkoutBeforeToday() {
        let missed = Adaptation.missedSessions(weeks: [plannedWeek()], workouts: [workout(.swim, daysAgo: 1)], today: "2026-09-30", calendar: TestFixtures.utc)

        XCTAssertEqual(missed, [
            MissedSession(date: "2026-09-28", sport: .bike, sessionType: .endurance, intensity: .easy, amount: 60),
            MissedSession(date: "2026-09-29", sport: .run, sessionType: .intervals, intensity: .hard, amount: 40)
        ])
    }

    func testTheSignalPrefersPainThenEffortThenMissedAndCountsEachOnce() {
        let run = workout(.run, daysAgo: 0)
        let hardRide = workout(.bike, daysAgo: 1, effort: 9)
        let missed = [MissedSession(date: "2026-09-29", sport: .swim, sessionType: .endurance, intensity: .easy, amount: 1_500)]
        let painful = [feedback(for: run, effort: 5, pain: .moderate, area: .knee)]

        let pain = Adaptation.signal(feedback: painful, missed: missed, workouts: [run, hardRide], today: "2026-09-30", handled: [], calendar: TestFixtures.utc)
        XCTAssertEqual(pain?.reason, .pain)

        let effort = Adaptation.signal(feedback: painful, missed: missed, workouts: [run, hardRide], today: "2026-09-30", handled: [pain!.key], calendar: TestFixtures.utc)
        XCTAssertEqual(effort?.reason, .effort)

        let skipped = Adaptation.signal(feedback: painful, missed: missed, workouts: [run, hardRide], today: "2026-09-30", handled: [pain!.key, effort!.key], calendar: TestFixtures.utc)
        XCTAssertEqual(skipped?.reason, .missed)

        XCTAssertNil(Adaptation.signal(feedback: painful, missed: missed, workouts: [run, hardRide], today: "2026-09-30", handled: [pain!.key, effort!.key, skipped!.key], calendar: TestFixtures.utc))
        // Leichte Beschwerden allein sind kein Anlass (der Server bremst sie trotzdem einen Tag).
        XCTAssertNil(Adaptation.signal(feedback: [feedback(for: run, pain: .light)], missed: [], workouts: [run], today: "2026-09-30", handled: [], calendar: TestFixtures.utc))
    }

    @MainActor
    func testTheFeedbackBookListsWorkoutsOfYesterdayAndTodayWithoutAnswer() {
        let book = SessionFeedbackBook(store: MemoryFeedbackStore(), calendar: TestFixtures.utc)
        let today = workout(.run, daysAgo: 0, hour: 8)
        let later = workout(.bike, daysAgo: 0, hour: 18)
        let yesterday = workout(.swim, daysAgo: 1)
        let old = workout(.swim, daysAgo: 3)

        XCTAssertEqual(book.pending(workouts: [old, yesterday, today, later], now: TestFixtures.now).map(\.id), [today.id, yesterday.id])

        book.record(feedback(for: today, effort: 6))
        XCTAssertEqual(book.pending(workouts: [old, yesterday, today], now: TestFixtures.now).map(\.id), [yesterday.id])
        XCTAssertEqual(book.feedback(for: today.id)?.effort, 6)
    }

    // MARK: - Anzeige

    func testHintsNoticesAndSummaries() {
        XCTAssertEqual(PlanV2Formatting.sessionHints(brick: true, indoor: false, sport: .run, previous: .bike), ["Koppeltraining: direkt nach Radfahren"])
        XCTAssertEqual(PlanV2Formatting.sessionHints(brick: false, indoor: true, sport: .bike, previous: nil), ["Drinnen (Rolle)"])
        XCTAssertEqual(PlanV2Formatting.sessionHints(brick: true, indoor: false, sport: .run, previous: nil), [])
        XCTAssertEqual(PlanV2Formatting.extraTitle(kind: .strength, minutes: 30), "Kraft · 30 min")
        XCTAssertNotNil(PlanV2Formatting.adaptationNotice(.pain))
        XCTAssertNil(PlanV2Formatting.adaptationNotice(.daily))
        let run = workout(.run, daysAgo: 0)
        XCTAssertEqual(PlanV2Formatting.feedbackSummary(feedback(for: run, effort: 7, pain: .light, area: .knee)), "Anstrengung 7 von 10, leichte Beschwerden (Knie)")
        XCTAssertEqual(PlanV2Formatting.feedbackSummary(feedback(for: run, effort: 4)), "Anstrengung 4 von 10, keine Beschwerden")
    }

    // MARK: - Wettkampftag

    func testTheRacePlanFromTheContractDecodes() throws {
        let response = try Self.contract(RacePlanResponse.self, "plan-v2-race-response.json")

        XCTAssertEqual(response.raceDay, "2027-07-04")
        XCTAssertEqual(response.plan.disciplines.map(\.sport), [.swim, .bike, .run])
        XCTAssertEqual(response.plan.disciplines.map(\.targetMinutes), [30, 80, 58])
        XCTAssertEqual(response.plan.disciplines[2].pacing.first?.targetText, "5:45 /km")
        XCTAssertEqual(response.plan.transitions.map(\.id), ["swim>bike", "bike>run"])
        XCTAssertEqual(response.plan.nutrition.during.map(\.sport), [.bike, .run])
        XCTAssertEqual(response.plan.nutrition.during.first?.summary, "60 g Kohlenhydrate, 600 ml, 500 mg Natrium pro Stunde")
        XCTAssertEqual(response.plan.totalMinutes, 168)
        XCTAssertEqual(response.weather?.summary, "15 bis 27 °C, Regen 10 %, Wind bis 15 km/h")
        XCTAssertNil(response.startTime)
    }

    func testTheRaceLoaderSendsTheRequestAndKeepsThePlanWithStartTime() async throws {
        let transport = StubTransport(status: 200, body: String(decoding: try RepoPaths.contractData("wire/plan-v2-race-response.json"), as: UTF8.self))
        let store = MemoryRaceStore()
        let client = PlanAPIClient(configuration: configuration, transport: transport)
        let loader = await RacePlanLoader(store: store, planProvider: { client }, now: { TestFixtures.now }, calendar: TestFixtures.utc)

        let done = await loader.generate(snapshot: TestFixtures.snapshot, startTime: "09:30", notes: "  Gels nur mit Wasser ", location: GeoPoint(latitude: 52.5, longitude: 13.4))

        XCTAssertTrue(done)
        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.test/v1/plan/race")
        XCTAssertEqual(sent.timeoutInterval, PlanAPIClient.macroTimeout)
        let body = try Self.body(sent)
        XCTAssertEqual(body["today"] as? String, "2026-09-30")
        XCTAssertEqual(body["start_time"] as? String, "09:30")
        XCTAssertEqual(body["notes"] as? String, "Gels nur mit Wasser")
        XCTAssertNotNil(body["location"])
        let saved = try XCTUnwrap(store.saved)
        XCTAssertEqual(saved.startTime, "09:30")
        XCTAssertEqual(saved.notes, "Gels nur mit Wasser")
        let matches = await loader.matches(raceDay: "2027-07-04")
        XCTAssertTrue(matches)
    }

    func testTheRaceClockFollowsTheStartTime() {
        XCTAssertEqual(RacePlanLoader.clock(minutesFromStart: -180, startTime: "09:30"), "06:30")
        XCTAssertEqual(RacePlanLoader.clock(minutesFromStart: 200, startTime: "09:30"), "12:50")
        XCTAssertEqual(RacePlanLoader.clock(minutesFromStart: -600, startTime: "07:00"), "21:00")
        XCTAssertEqual(RacePlanLoader.clock(minutesFromStart: -90, startTime: nil), "-90 min")
        XCTAssertEqual(RacePlanLoader.clock(minutesFromStart: 30, startTime: nil), "+30 min")
        XCTAssertEqual(RacePlanLoader.clock(minutesFromStart: 0, startTime: nil), "Start")
    }
}

/// Rückmeldungen im Speicher.
final class MemoryFeedbackStore: SessionFeedbackStoring {
    private(set) var entries: [SessionFeedback] = []
    func all() -> [SessionFeedback] { entries }
    func save(_ feedback: SessionFeedback) throws {
        entries = entries.filter { $0.workoutID != feedback.workoutID } + [feedback]
    }
}

final class MemoryRaceStore: RacePlanStoring {
    var saved: RacePlanResponse?
    func load() -> RacePlanResponse? { saved }
    func save(_ response: RacePlanResponse) throws { saved = response }
}
