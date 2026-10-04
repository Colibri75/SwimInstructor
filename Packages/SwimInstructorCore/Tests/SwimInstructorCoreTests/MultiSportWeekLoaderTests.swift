import XCTest
@testable import SwimInstructorCore

/// Bausteine für die Tests der nächsten sieben Tage in Plan v2. "Heute" ist Mittwoch, der 30.09.2026 (TestFixtures.now).
private enum WeekLoaderV2Data {
    static let bikeTest = PlannedTest(
        id: "threshold_30min", displayName: "30-Minuten-Test", maximalEffort: true, produces: [.thresholdHeartRate, .thresholdPower]
    )

    /// Die sieben Tage ab heute, die der Lader anfragt.
    static let window = ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06"]

    /// Eine Einheit; Schwimmen in Metern, Rad und Laufen in Minuten.
    static func session(
        _ sport: SportID,
        _ type: SessionType = .endurance,
        _ intensity: PlanIntensity = .easy,
        amount: Double,
        minutes: Double,
        meters: Double,
        focus: String = "Grundlage",
        test: PlannedTest? = nil
    ) -> WeekSession {
        let unit: PlanUnit = sport == SportID.swim ? PlanUnit.meters : PlanUnit.minutes
        return WeekSession(
            sport: sport, sessionType: type, intensity: intensity, amount: amount, unit: unit,
            minutes: minutes, distanceMeters: meters, focus: focus, test: test
        )
    }

    static func day(_ date: String, _ sessions: [WeekSession], focus: String = "Training", isEdited: Bool = false) -> PlannedDay {
        PlannedDay(date: date, content: PlannedDayContent(focus: focus, sessions: sessions), isEdited: isEdited)
    }

    static func restDay(_ date: String) -> PlannedDay {
        PlannedDay(date: date, content: PlannedDayContent.rest())
    }

    static func week(_ weekStart: String = "2026-09-28", days: [PlannedDay]) -> WeekPlanV2 {
        WeekPlanV2(weekStart: weekStart, generatedAt: TestFixtures.date(daysAgo: 2, hour: 6), rationale: "alt", days: days)
    }

    /// Die laufende Woche: Mo Radtest, Di harte Intervalle Laufen und lockeres Schwimmen, Mi (heute) Technik
    /// Schwimmen und Laufen moderat, Do Ruhe, Fr Laufen lang, Sa Ausfahrt, So Ruhe.
    static func currentWeek() -> WeekPlanV2 {
        week(days: [
            day("2026-09-28", [
                // Test mit Vollbelastung zählt als hart, auch ohne harte Intensität.
                session(.bike, .test, .moderate, amount: 58, minutes: 58, meters: 24_360, focus: "30-Minuten-Test", test: bikeTest)
            ], focus: "Radtest"),
            day("2026-09-29", [
                session(.run, .intervals, .hard, amount: 30, minutes: 30, meters: 5_040, focus: "Tempo"),
                session(.swim, amount: 2_000, minutes: 40, meters: 2_000)
            ], focus: "Laufen und Schwimmen"),
            day("2026-09-30", [
                session(.swim, .technique, .easy, amount: 1_500, minutes: 30, meters: 1_500, focus: "Technik"),
                session(.run, .endurance, .moderate, amount: 40, minutes: 40, meters: 6_720)
            ], focus: "Schwimmen und Laufen"),
            restDay("2026-10-01"),
            day("2026-10-02", [session(.run, amount: 45, minutes: 45, meters: 7_560, focus: "Lang")], focus: "Laufen lang"),
            day("2026-10-03", [session(.bike, amount: 90, minutes: 90, meters: 37_800)], focus: "Ausfahrt"),
            restDay("2026-10-04")
        ])
    }

    static func workout(
        _ sport: SportID, daysAgo: Int, hour: Int, minutes: Double, meters: Double? = nil, heartRate: Double? = nil
    ) -> Workout {
        let start = TestFixtures.date(daysAgo: daysAgo, hour: hour)
        return Workout(
            id: UUID(), sport: sport, startDate: start, endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60, distanceMeters: meters, averageHeartRate: heartRate
        )
    }
}

@MainActor
final class MultiSportWeekLoaderTests: XCTestCase {
    private final class MemoryStore: WeekPlanV2Storing {
        var stored: [WeekPlanV2]
        private(set) var saves = 0
        init(_ stored: [WeekPlanV2] = []) { self.stored = stored }
        func load() -> [WeekPlanV2] { stored }
        func save(_ plans: [WeekPlanV2]) throws {
            stored = plans
            saves += 1
        }
    }

    /// Antwortet mit dem Vertragsbeispiel (Mi 30.09. bis Di 06.10., zwei Kalenderwochen) oder einem Fehler.
    private final class FakeProvider: WeekPlanV2Providing, @unchecked Sendable {
        private(set) var requests: [WeekPlanV2Request] = []
        let failure: Error?
        init(failure: Error? = nil) { self.failure = failure }

        func fetchWeekPlanV2(_ request: WeekPlanV2Request) async throws -> WeekPlanV2Response {
            requests.append(request)
            if let failure { throw failure }
            let data = try RepoPaths.contractData("wire/plan-v2-week-response.json")
            return try PlanResponse.jsonDecoder().decode(WeekPlanV2Response.self, from: data)
        }
    }

    private final class MemoryMarker: DailyRefreshMarking {
        var marker: String?
        func lastDay() -> String? { marker }
        func setLastDay(_ marker: String) { self.marker = marker }
    }

    private func makeLoader(
        store: MemoryStore = MemoryStore(),
        provider: FakeProvider?,
        workouts: [Workout] = [],
        snapshot: AthleteStateSnapshot = TestFixtures.snapshot,
        withContext: Bool = true,
        marker: MemoryMarker = MemoryMarker()
    ) -> MultiSportWeekLoader {
        let loader = MultiSportWeekLoader(
            store: store,
            planProvider: { provider },
            dailyMarker: marker,
            now: { TestFixtures.now },
            calendar: TestFixtures.utc
        )
        if withContext {
            loader.contextProvider = { MultiSportWeekLoader.PlanningContext(snapshot: snapshot, workouts: workouts) }
        }
        return loader
    }

    // MARK: - Lesen

    func testStartsOnTheCurrentWeekWithoutAPlan() {
        let loader = makeLoader(provider: nil)

        XCTAssertEqual(loader.todayKey, "2026-09-30")
        XCTAssertEqual(loader.currentWeekStart, "2026-09-28")
        XCTAssertEqual(loader.selectedWeekStart, "2026-09-28")
        XCTAssertTrue(loader.weeks.isEmpty)
        XCTAssertNil(loader.selectedWeek)
        XCTAssertNil(loader.todayEntry)
        XCTAssertNil(loader.todayTarget)
        XCTAssertFalse(loader.needsConfiguration)
        XCTAssertNil(loader.error)
    }

    func testTodayEntryAndTargetComeFromTheStoredWeek() {
        let loader = makeLoader(store: MemoryStore([WeekLoaderV2Data.currentWeek()]), provider: nil)

        XCTAssertEqual(loader.selectedWeek?.weekStart, "2026-09-28")
        XCTAssertEqual(loader.todayEntry?.date, "2026-09-30")
        XCTAssertEqual(loader.todayTarget, DayTargetV2(focus: "Schwimmen und Laufen", sessions: [
            DayTargetV2.Session(sport: .swim, sessionType: .technique, intensity: .easy, amount: 1_500, focus: "Technik"),
            DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .moderate, amount: 40, focus: "Grundlage")
        ]))
        // Ein Test nimmt seine Kennung mit in die Vorgabe.
        XCTAssertEqual(loader.day(on: "2026-09-28")?.target.sessions.first?.testID, "threshold_30min")
        XCTAssertNil(loader.day(on: "2026-10-12"))
        XCTAssertNil(loader.day(on: "kaputt"))
    }

    func testADayWithoutTimeGivesARestDayAsTarget() {
        let loader = makeLoader(store: MemoryStore([WeekLoaderV2Data.currentWeek()]), provider: nil)

        loader.markUnavailable("2026-09-30")

        XCTAssertEqual(loader.todayEntry?.isUnavailable, true)
        XCTAssertEqual(loader.todayTarget, DayTargetV2(focus: "Keine Zeit", sessions: []))
    }

    func testEditableFromTodayOn() {
        let loader = makeLoader(provider: nil)

        XCTAssertFalse(loader.isEditable("2026-09-29"))
        XCTAssertTrue(loader.isEditable("2026-09-30"))
        XCTAssertTrue(loader.isEditable("2026-10-06"))
    }

    func testPlannedHardComesFromHardSessionsAndMaximalTests() {
        let loader = makeLoader(store: MemoryStore([WeekLoaderV2Data.currentWeek()]), provider: nil)

        XCTAssertTrue(loader.plannedHard(on: "2026-09-28", sport: .bike))
        XCTAssertTrue(loader.plannedHard(on: "2026-09-29", sport: .run))
        XCTAssertFalse(loader.plannedHard(on: "2026-09-29", sport: .swim))
        XCTAssertFalse(loader.plannedHard(on: "2026-09-30", sport: .run))
        // Ohne Plan für den Tag ist nichts hart.
        XCTAssertFalse(loader.plannedHard(on: "2026-09-21", sport: .run))
    }

    // MARK: - Planen

    func testPlanningAsksForTheSevenDaysFromTodayWithEverythingTheServerNeeds() async throws {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider)
        let macro = MacroWeekV2(
            weekStart: "2026-09-28", phase: .specific, deload: false, focus: "Wettkampfnah", totalMinutes: 210, load: 190,
            sports: [MacroSportVolume(sport: .swim, unit: .meters, amount: 3_500, minutes: 70, distanceMeters: 3_500, sessions: 2)],
            tests: [MacroTestSlot(sport: .bike, testID: "threshold_30min", displayName: "30-Minuten-Test")]
        )
        let settings = TestSettings(offer: true, intervalWeeks: 8, preferred: [TestSettings.Preference(sport: .run, testID: "threshold_30min")])
        var askedDates: [String] = []
        loader.equipmentProvider = { ["pull_buoy", "paddles"] }
        loader.macroProvider = { dates in
            askedDates = dates
            return [macro]
        }
        loader.testSettingsProvider = { settings }

        let planned = await loader.planNextDays(wishes: "Freitag habe ich viel Zeit")

        XCTAssertTrue(planned)
        XCTAssertEqual(provider.requests.count, 1)
        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertEqual(request.snapshot, TestFixtures.snapshot)
        XCTAssertEqual(request.fromDate, "2026-09-30")
        XCTAssertEqual(request.today, "2026-09-30")
        XCTAssertEqual(request.unavailableDates, [])
        XCTAssertEqual(request.recentTraining, [])
        XCTAssertEqual(request.macroWeeks, [macro])
        XCTAssertEqual(request.wishes, "Freitag habe ich viel Zeit")
        XCTAssertEqual(request.equipment, ["pull_buoy", "paddles"])
        XCTAssertEqual(request.testSettings, settings)
        XCTAssertEqual(askedDates, WeekLoaderV2Data.window)
        XCTAssertNil(loader.error)
        XCTAssertFalse(loader.isLoading)
    }

    func testWithoutProvidersTheOptionalFieldsStayEmpty() async throws {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider)

        await loader.planNextDays()

        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertNil(request.wishes)
        XCTAssertNil(request.equipment)
        XCTAssertNil(request.testSettings)
        XCTAssertEqual(request.macroWeeks, [])
    }

    func testTheResponseIsSplitIntoCalendarWeeks() async throws {
        // Mi 30.09. bis Di 06.10.: fünf Tage in dieser Woche, zwei in der nächsten.
        let store = MemoryStore()
        let loader = makeLoader(store: store, provider: FakeProvider())

        let planned = await loader.planNextDays()

        XCTAssertTrue(planned)
        XCTAssertEqual(loader.weeks.map(\.weekStart), ["2026-09-28", "2026-10-05"])
        let current = try XCTUnwrap(loader.week(starting: "2026-09-28"))
        let next = try XCTUnwrap(loader.week(starting: "2026-10-05"))
        XCTAssertEqual(current.days.map(\.date), ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
        XCTAssertEqual(next.days.map(\.date), ["2026-10-05", "2026-10-06"])
        XCTAssertEqual(current.sports, [SportID.swim, SportID.bike, SportID.run])
        XCTAssertEqual(next.sports, [SportID.swim])
        // Beide Wochen zusammen haben die 202 Minuten der Antwort.
        XCTAssertEqual(current.plannedMinutes + next.plannedMinutes, 202)
        XCTAssertEqual(current.rationale, next.rationale)
        XCTAssertEqual(current.wishes, "Freitag habe ich viel Zeit")
        XCTAssertEqual(current.day(on: "2026-10-02")?.sessions.first?.test?.id, "threshold_30min")
        XCTAssertEqual(loader.todayEntry?.isRestDay, true)
        XCTAssertEqual(loader.todayTarget, DayTargetV2(focus: "Ruhetag", sessions: []))
        XCTAssertEqual(store.stored, loader.weeks)
        XCTAssertEqual(store.saves, 1)
    }

    func testReplanningKeepsPastEditsDaysWithoutTimeAndDaysBeyondTheWindow() async throws {
        // Montag (vorbei) von Hand geändert, Freitag keine Zeit, in der nächsten Woche schon der Donnerstag geplant.
        let monday = WeekLoaderV2Data.day(
            "2026-09-28", [WeekLoaderV2Data.session(.run, amount: 25, minutes: 25, meters: 4_200)], focus: "Kurz gelaufen", isEdited: true
        )
        let friday = WeekLoaderV2Data.day(
            "2026-10-02", [WeekLoaderV2Data.session(.run, amount: 45, minutes: 45, meters: 7_560, focus: "Lang")], focus: "Laufen lang"
        )
        let current = WeekLoaderV2Data.week(days: [monday, WeekLoaderV2Data.restDay("2026-09-29"), friday])
        let later = WeekLoaderV2Data.week("2026-10-05", days: [
            WeekLoaderV2Data.day("2026-10-08", [WeekLoaderV2Data.session(.bike, amount: 60, minutes: 60, meters: 25_200)])
        ])
        let store = MemoryStore([current, later])
        let provider = FakeProvider()
        let loader = makeLoader(store: store, provider: provider)
        loader.markUnavailable("2026-10-02")

        await loader.planNextDays()

        XCTAssertEqual(provider.requests.first?.unavailableDates, ["2026-10-02"])
        let week = try XCTUnwrap(loader.week(starting: "2026-09-28"))
        XCTAssertEqual(week.days.map(\.date), [
            "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"
        ])
        XCTAssertNotEqual(week.rationale, "alt")
        // Vorbei: bleibt mit der Änderung des Athleten.
        XCTAssertEqual(week.day(on: "2026-09-28"), monday)
        // Keine Zeit: bleibt Ruhetag, obwohl der Server dort den Radtest vorsah; das Geplante bleibt gemerkt.
        let unavailable = try XCTUnwrap(week.day(on: "2026-10-02"))
        XCTAssertTrue(unavailable.isUnavailable)
        XCTAssertTrue(unavailable.isRestDay)
        XCTAssertTrue(unavailable.isEdited)
        XCTAssertEqual(unavailable.contentBeforeUnavailable, friday.content)
        // Die übrigen Tage im Fenster kommen vom Server.
        XCTAssertEqual(week.day(on: "2026-10-01")?.sessions.map(\.sport), [SportID.swim])
        XCTAssertEqual(week.day(on: "2026-10-03")?.sessions.map(\.sport), [SportID.run, SportID.swim])
        // Nach dem Fenster (endet am 06.10.): Der ältere Plan bleibt.
        XCTAssertEqual(loader.week(starting: "2026-10-05")?.days.map(\.date), ["2026-10-05", "2026-10-06", "2026-10-08"])
        XCTAssertEqual(loader.day(on: "2026-10-08")?.sessions.first?.sport, SportID.bike)
        XCTAssertEqual(store.stored, loader.weeks)

        // Wieder Zeit: Das Geplante von vorher kommt zurück.
        loader.clearUnavailable("2026-10-02")
        XCTAssertEqual(loader.day(on: "2026-10-02")?.content, friday.content)
    }

    func testAnEditedDayInsideTheWindowTakesTheNewPlan() async throws {
        // Neu planen bringt die Woche wieder ins Gleichgewicht: Im Fenster gilt der Plan des Servers (nur Tage ohne
        // Zeit behalten ihre Markierung).
        let loader = makeLoader(store: MemoryStore([WeekLoaderV2Data.currentWeek()]), provider: FakeProvider())
        loader.changeSport("2026-10-02", session: 0, to: .bike)
        XCTAssertEqual(loader.day(on: "2026-10-02")?.isEdited, true)

        await loader.planNextDays()

        let friday = try XCTUnwrap(loader.day(on: "2026-10-02"))
        XCTAssertFalse(friday.isEdited)
        XCTAssertEqual(friday.focus, "Leistungstest Rad")
        XCTAssertEqual(friday.sessions.first?.test?.id, "threshold_30min")
    }

    func testOnlyDaysWithoutTimeInsideTheWindowAreSent() async throws {
        let provider = FakeProvider()
        let loader = makeLoader(store: MemoryStore([WeekLoaderV2Data.currentWeek()]), provider: provider)
        loader.markUnavailable("2026-09-29")
        loader.markUnavailable("2026-10-03")
        loader.markUnavailable("2026-10-01")

        await loader.planNextDays()

        XCTAssertEqual(provider.requests.first?.unavailableDates, ["2026-10-01", "2026-10-03"])
        XCTAssertEqual(loader.day(on: "2026-10-03")?.isUnavailable, true)
        XCTAssertEqual(loader.day(on: "2026-10-03")?.isRestDay, true)
    }

    func testRecentTrainingIsFilledFromTheContextWorkoutsWithHardFromThePlan() async throws {
        let workouts = [
            WeekLoaderV2Data.workout(.run, daysAgo: 8, hour: 8, minutes: 50, meters: 8_000),        // 22.09., zu lange her
            WeekLoaderV2Data.workout(.swim, daysAgo: 7, hour: 8, minutes: 30, meters: 1_200),       // 23.09., erster Tag
            WeekLoaderV2Data.workout(.run, daysAgo: 3, hour: 8, minutes: 50, meters: 8_000),        // 27.09., ohne Plan
            WeekLoaderV2Data.workout(.bike, daysAgo: 2, hour: 9, minutes: 60, meters: 25_000),      // Radtest geplant
            WeekLoaderV2Data.workout(SportID(rawValue: "kayak"), daysAgo: 2, hour: 12, minutes: 40), // unbekannte Sportart
            WeekLoaderV2Data.workout(.run, daysAgo: 1, hour: 7, minutes: 32, meters: 5_200),        // harte Intervalle geplant
            WeekLoaderV2Data.workout(.swim, daysAgo: 1, hour: 18, minutes: 41, meters: 2_050),      // locker geplant
            WeekLoaderV2Data.workout(.swim, daysAgo: 0, hour: 8, minutes: 30, meters: 1_500)        // heute, gehört nicht dazu
        ]
        let provider = FakeProvider()
        let loader = makeLoader(store: MemoryStore([WeekLoaderV2Data.currentWeek()]), provider: provider, workouts: workouts)

        await loader.planNextDays()

        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertEqual(request.recentTraining, [
            RecentTrainingEntry(date: "2026-09-23", sport: .swim, minutes: 30, meters: 1_200, hard: false),
            RecentTrainingEntry(date: "2026-09-27", sport: .run, minutes: 50, meters: 8_000, hard: false),
            RecentTrainingEntry(date: "2026-09-28", sport: .bike, minutes: 60, meters: 25_000, hard: true),
            RecentTrainingEntry(date: "2026-09-29", sport: .run, minutes: 32, meters: 5_200, hard: true),
            RecentTrainingEntry(date: "2026-09-29", sport: .swim, minutes: 41, meters: 2_050, hard: false)
        ])
    }

    func testAHighHeartRateMakesASessionHardWithoutAHardPlan() async throws {
        let maximum = AthleteStateSnapshot.PerformanceSummary.Value(
            metric: .maxHeartRate, value: 190, source: .tested, measuredAt: TestFixtures.now
        )
        let snapshot = TestFixtures.snapshot.withPerformance(AthleteStateSnapshot.PerformanceSummary(athlete: [maximum], sports: []))
        let workouts = [
            // 171 von 190: 90 % des Maximalpulses, ab 88 % hart.
            WeekLoaderV2Data.workout(.run, daysAgo: 4, hour: 8, minutes: 45, meters: 9_000, heartRate: 171),
            WeekLoaderV2Data.workout(.run, daysAgo: 3, hour: 8, minutes: 45, meters: 8_000, heartRate: 150)
        ]
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider, workouts: workouts, snapshot: snapshot)

        await loader.planNextDays()

        XCTAssertEqual(provider.requests.first?.recentTraining.map(\.hard), [true, false])
    }

    func testRecentTrainingForTodayIncludesTodayButNotLaterToday() {
        let workouts = [
            WeekLoaderV2Data.workout(.swim, daysAgo: 7, hour: 8, minutes: 30, meters: 1_200),
            WeekLoaderV2Data.workout(.run, daysAgo: 0, hour: 7, minutes: 40, meters: 6_800),
            // Heute Abend, noch nicht geschehen.
            WeekLoaderV2Data.workout(.bike, daysAgo: 0, hour: 18, minutes: 60, meters: 25_000)
        ]
        let loader = makeLoader(store: MemoryStore([WeekLoaderV2Data.currentWeek()]), provider: nil)

        let entries = loader.recentTrainingForToday(snapshot: TestFixtures.snapshot, workouts: workouts)

        XCTAssertEqual(entries, [
            RecentTrainingEntry(date: "2026-09-23", sport: .swim, minutes: 30, meters: 1_200, hard: false),
            RecentTrainingEntry(date: "2026-09-30", sport: .run, minutes: 40, meters: 6_800, hard: false)
        ])
    }

    func testWithoutHealthDataThereIsAHintAndNoRequest() async throws {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider, withContext: false)

        let planned = await loader.planNextDays()

        XCTAssertFalse(planned)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(loader.error, "Die Health-Daten sind noch nicht geladen. Öffne zuerst den Tab Heute.")
        XCTAssertFalse(loader.needsConfiguration)
        XCTAssertTrue(loader.weeks.isEmpty)
    }

    func testWithoutATokenItAsksForConfigurationUntilOneIsThere() async throws {
        var provider: FakeProvider? = nil
        let loader = MultiSportWeekLoader(
            store: MemoryStore(),
            planProvider: { provider },
            dailyMarker: MemoryMarker(),
            now: { TestFixtures.now },
            calendar: TestFixtures.utc
        )
        loader.contextProvider = { MultiSportWeekLoader.PlanningContext(snapshot: TestFixtures.snapshot, workouts: []) }

        let withoutToken = await loader.planNextDays()

        XCTAssertFalse(withoutToken)
        XCTAssertTrue(loader.needsConfiguration)
        XCTAssertTrue(loader.weeks.isEmpty)
        XCTAssertNil(loader.error)

        provider = FakeProvider()
        let withToken = await loader.planNextDays()

        XCTAssertTrue(withToken)
        XCTAssertFalse(loader.needsConfiguration)
        XCTAssertEqual(loader.weeks.count, 2)
    }

    func testAFailureKeepsTheOldPlanAndShowsTheError() async throws {
        let store = MemoryStore([WeekLoaderV2Data.currentWeek()])
        let loader = makeLoader(store: store, provider: FakeProvider(failure: PlanAPIError.planUnavailable(reason: "timeout")))

        let planned = await loader.planNextDays()

        XCTAssertFalse(planned)
        XCTAssertEqual(loader.weeks, [WeekLoaderV2Data.currentWeek()])
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(loader.error, PlanAPIError.planUnavailable(reason: "timeout").errorDescription)
        XCTAssertFalse(loader.isLoading)
    }

    func testASuccessfulPlanClearsAnEarlierError() async throws {
        let loader = makeLoader(provider: FakeProvider(), withContext: false)
        await loader.planNextDays()
        XCTAssertNotNil(loader.error)

        loader.contextProvider = { MultiSportWeekLoader.PlanningContext(snapshot: TestFixtures.snapshot, workouts: []) }
        await loader.planNextDays()

        XCTAssertNil(loader.error)
    }

    // MARK: - Einmal am Tag

    func testTheDailyRefreshPlansOncePerDay() async throws {
        let provider = FakeProvider()
        let marker = MemoryMarker()
        let loader = makeLoader(provider: provider, marker: marker)

        await loader.refreshDaily()
        await loader.refreshDaily()
        await loader.refreshDaily()

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(marker.marker, "2026-09-30|")
    }

    func testANewStampOrANewDayPlansAgain() async throws {
        let provider = FakeProvider()
        let marker = MemoryMarker()
        marker.marker = "2026-09-29|ziel-a"
        let loader = makeLoader(provider: provider, marker: marker)

        // Neuer Tag: planen.
        await loader.refreshDaily(stamp: "ziel-a")
        // Selber Tag, selbes Merkmal: nichts.
        await loader.refreshDaily(stamp: "ziel-a")
        // Anderes Merkmal (neues Ziel, überarbeiteter Gesamtplan): neu planen.
        await loader.refreshDaily(stamp: "ziel-b")

        XCTAssertEqual(provider.requests.count, 2)
        XCTAssertEqual(marker.marker, "2026-09-30|ziel-b")
    }

    func testAFailedDailyRefreshDoesNotSetTheMarker() async throws {
        let marker = MemoryMarker()
        let failing = makeLoader(provider: FakeProvider(failure: PlanAPIError.network("aus")), marker: marker)

        await failing.refreshDaily(stamp: "ziel")
        XCTAssertNil(marker.marker)
        XCTAssertNotNil(failing.error)

        // Ohne Health-Daten zählt der Tag ebenfalls nicht als erledigt.
        let withoutContext = makeLoader(provider: FakeProvider(), withContext: false, marker: marker)
        await withoutContext.refreshDaily(stamp: "ziel")
        XCTAssertNil(marker.marker)

        let provider = FakeProvider()
        let working = makeLoader(provider: provider, marker: marker)
        await working.refreshDaily(stamp: "ziel")

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(marker.marker, "2026-09-30|ziel")
    }

    func testTheDailyRefreshGivesTheWishToThePlan() async throws {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider)

        await loader.refreshDaily(wishes: "Knie schonen")

        XCTAssertEqual(provider.requests.first?.wishes, "Knie schonen")
    }

    // MARK: - Ändern

    func testChangingTheSportOfASessionIsSaved() throws {
        let store = MemoryStore([WeekLoaderV2Data.currentWeek()])
        let loader = makeLoader(store: store, provider: nil)

        // Freitag Laufen 45 min wird Rad: Dauer bleibt, Strecke mit 7 m/s.
        loader.changeSport("2026-10-02", session: 0, to: .bike)

        let ride = try XCTUnwrap(loader.day(on: "2026-10-02")?.sessions.first)
        XCTAssertEqual(ride.sport, SportID.bike)
        XCTAssertEqual(ride.unit, PlanUnit.minutes)
        XCTAssertEqual(ride.amount, 45)
        XCTAssertEqual(ride.minutes, 45)
        XCTAssertEqual(ride.distanceMeters, 18_900)
        XCTAssertEqual(loader.day(on: "2026-10-02")?.isEdited, true)
        XCTAssertEqual(store.saves, 1)
        XCTAssertEqual(store.stored, loader.weeks)

        // Heute Laufen 40 min wird Schwimmen: 40 min mit 0,8 m/s, auf 100 m gerundet.
        loader.changeSport("2026-09-30", session: 1, to: .swim)

        let swim = try XCTUnwrap(loader.todayEntry?.sessions.last)
        XCTAssertEqual(swim.sport, SportID.swim)
        XCTAssertEqual(swim.unit, PlanUnit.meters)
        XCTAssertEqual(swim.amount, 1_900)
        XCTAssertEqual(swim.distanceMeters, 1_900)
        XCTAssertEqual(store.saves, 2)

        // Ein neuer Lader findet die Änderungen im Speicher.
        let reloaded = makeLoader(store: store, provider: nil)
        XCTAssertEqual(reloaded.day(on: "2026-10-02")?.sessions.first?.sport, SportID.bike)
        XCTAssertEqual(reloaded.todayEntry?.sessions.map(\.sport), [SportID.swim, SportID.swim])
    }

    func testEditsThroughTheLoaderAreAppliedAndSaved() throws {
        let store = MemoryStore([WeekLoaderV2Data.currentWeek()])
        let loader = makeLoader(store: store, provider: nil)

        loader.setAmount("2026-10-03", session: 0, amount: 120)
        loader.addSession("2026-10-01", sport: .swim)
        loader.removeSession("2026-09-30", session: 1)
        loader.setRest("2026-10-02")
        loader.swapDays("2026-10-01", "2026-10-03")
        // Tage verschiedener Wochen lassen sich nicht tauschen.
        loader.swapDays("2026-10-04", "2026-10-05")

        let thursday = try XCTUnwrap(loader.day(on: "2026-10-01"))
        let saturday = try XCTUnwrap(loader.day(on: "2026-10-03"))
        XCTAssertEqual(thursday.sessions.map(\.sport), [SportID.bike])
        XCTAssertEqual(thursday.sessions.first?.amount, 120)
        XCTAssertEqual(thursday.sessions.first?.minutes, 120)
        XCTAssertEqual(saturday.sessions.map(\.sport), [SportID.swim])
        XCTAssertEqual(saturday.sessions.first?.amount, 1_000)
        XCTAssertTrue(thursday.isEdited)
        XCTAssertTrue(saturday.isEdited)
        XCTAssertEqual(loader.todayEntry?.sessions.map(\.sport), [SportID.swim])
        XCTAssertEqual(loader.day(on: "2026-10-02")?.isRestDay, true)
        XCTAssertEqual(store.saves, 5)
        XCTAssertEqual(store.stored, loader.weeks)
    }

    func testAMissedDayCanBeMovedToARestDay() {
        let store = MemoryStore([WeekLoaderV2Data.currentWeek()])
        let loader = makeLoader(store: store, provider: nil)

        loader.moveToRestDay(from: "2026-09-29", to: "2026-10-04")

        XCTAssertEqual(loader.day(on: "2026-10-04")?.sessions.map(\.sport), [SportID.run, SportID.swim])
        XCTAssertEqual(loader.day(on: "2026-09-29")?.isRestDay, true)
        XCTAssertEqual(loader.day(on: "2026-09-29")?.focus, "Verschoben")
        XCTAssertEqual(store.saves, 1)
    }

    func testAnEditWithoutAPlanOrWithoutEffectIsNotSaved() {
        let empty = MemoryStore()
        let withoutPlan = makeLoader(store: empty, provider: nil)
        withoutPlan.markUnavailable("2026-10-02")
        withoutPlan.changeSport("2026-10-02", session: 0, to: .bike)
        XCTAssertEqual(empty.saves, 0)
        XCTAssertTrue(withoutPlan.weeks.isEmpty)

        let filled = MemoryStore([WeekLoaderV2Data.currentWeek()])
        let loader = makeLoader(store: filled, provider: nil)
        loader.clearUnavailable("2026-10-02")
        // Schon Laufen, keine solche Einheit, unbekannte Sportart: nichts ändert sich.
        loader.changeSport("2026-10-02", session: 0, to: .run)
        loader.changeSport("2026-10-02", session: 5, to: .bike)
        loader.changeSport("2026-10-02", session: 0, to: SportID(rawValue: "kayak"))
        XCTAssertEqual(filled.saves, 0)
        XCTAssertEqual(loader.weeks, [WeekLoaderV2Data.currentWeek()])
    }

    func testOnlyTheLastEightWeeksAreKept() async throws {
        let calendar = WeekCalendar(calendar: TestFixtures.utc)
        let old = (1...8).map { offset -> WeekPlanV2 in
            let start = calendar.addingDays(-7 * offset, to: "2026-09-28") ?? ""
            return WeekLoaderV2Data.week(start, days: [])
        }
        let store = MemoryStore(old)
        let loader = makeLoader(store: store, provider: FakeProvider())

        await loader.planNextDays()

        // Acht alte und zwei neue Wochen: Die zwei ältesten fallen weg.
        XCTAssertEqual(MultiSportWeekLoader.retainedWeeks, 8)
        XCTAssertEqual(loader.weeks.count, 8)
        XCTAssertEqual(loader.weeks.first?.weekStart, "2026-08-17")
        XCTAssertEqual(loader.weeks.last?.weekStart, "2026-10-05")
        XCTAssertFalse(loader.weeks.contains { $0.weekStart == "2026-08-03" })
        XCTAssertEqual(store.stored.map(\.weekStart), loader.weeks.map(\.weekStart))
    }

    // MARK: - Woche wechseln

    func testShiftingTheWeekIsLimitedToFourWeeksBackAndOneAhead() {
        let loader = makeLoader(provider: nil)

        loader.shiftSelectedWeek(by: 1)
        XCTAssertEqual(loader.selectedWeekStart, "2026-10-05")
        loader.shiftSelectedWeek(by: 1)
        XCTAssertEqual(loader.selectedWeekStart, "2026-10-05")

        for _ in 0..<6 { loader.shiftSelectedWeek(by: -1) }
        XCTAssertEqual(loader.selectedWeekStart, "2026-08-31")

        loader.shiftSelectedWeek(by: 4)
        XCTAssertEqual(loader.selectedWeekStart, "2026-09-28")
    }
}
