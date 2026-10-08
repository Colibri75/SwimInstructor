import XCTest
@testable import SwimInstructorCore

/// Tagespläne und Einheiten für die Tests von "Heute" mit Plan v2. "Heute" ist Mittwoch, der 30.09.2026.
private enum TodayLoaderV2Data {
    /// Gestern Schwimmen, vorgestern Laufen.
    static let workouts: [Workout] = [
        TestFixtures.workout(.swim, daysAgo: 1, minutes: 30, meters: 1_500),
        TestFixtures.workout(.run, daysAgo: 2, minutes: 40, meters: 7_000)
    ]

    /// Technik Schwimmen und lockeres Laufen.
    static func response(date: String = "2026-09-30", source: PlanSource = .claude) -> DayPlanV2Response {
        let swim = DaySession(
            sport: .swim, sessionType: .technique, intensity: .easy, focus: "Technik",
            amount: 1_500, unit: .meters, distanceMeters: 1_500, durationMinutes: 30,
            steps: [PlanStep(name: "Technik", repetitions: 6, measure: .distance, distanceMeters: 250, cue: "Abschlag")]
        )
        let run = DaySession(
            sport: .run, sessionType: .endurance, intensity: .easy, focus: "Locker",
            amount: 30, unit: .minutes, distanceMeters: 5_000, durationMinutes: 30,
            steps: [PlanStep(name: "Locker", repetitions: 1, measure: .duration, durationSeconds: 1_800, cue: "Locker laufen")]
        )
        return DayPlanV2Response(
            source: source,
            date: date,
            generatedAt: TestFixtures.now,
            stale: source == .fallback,
            plan: DayPlanV2(rationale: "Test", sessions: [swim, run]),
            fallbackReason: source == .fallback ? "timeout" : nil
        )
    }
}

@MainActor
final class MultiSportTodayLoaderTests: XCTestCase {
    private final class MemoryCache: DayPlanV2Caching {
        var stored: DayPlanV2Response?
        private(set) var saves = 0
        init(_ stored: DayPlanV2Response? = nil) { self.stored = stored }
        func load() -> DayPlanV2Response? { stored }
        func save(_ response: DayPlanV2Response) throws {
            stored = response
            saves += 1
        }
    }

    /// Wie `FileDayPlanV2History`: pro Tag der letzte Plan, ohne Fallback-Pläne.
    private final class MemoryHistory: DayPlanV2HistoryStoring {
        var stored: [DayPlanV2Response]
        init(_ stored: [DayPlanV2Response] = []) { self.stored = stored }
        func load() -> [DayPlanV2Response] { stored }
        func record(_ response: DayPlanV2Response) throws {
            guard response.source != .fallback else { return }
            stored.removeAll { $0.date == response.date }
            stored.append(response)
            stored.sort { $0.date < $1.date }
        }
    }

    private final class CountingProvider: DayPlanV2Providing, @unchecked Sendable {
        var result: Result<DayPlanV2Response, Error>
        private(set) var requests: [DayPlanV2Request] = []
        /// Läuft während einer Anfrage, etwa um eine Änderung im Plan-Tab nachzustellen.
        var whileFetching: @MainActor (Int) -> Void = { _ in }
        init(_ result: Result<DayPlanV2Response, Error>) { self.result = result }
        var calls: Int { requests.count }
        var newPlanCalls: Int { requests.filter(\.regenerate).count }

        func fetchDayPlanV2(_ request: DayPlanV2Request) async throws -> DayPlanV2Response {
            requests.append(request)
            let call = requests.count
            await whileFetching(call)
            return try result.get()
        }
    }

    private final class MemoryWishes: DailyWishStoring {
        var stored: [String: String]
        init(_ stored: [String: String] = [:]) { self.stored = stored }
        func wish(for day: String) -> String? { stored[day] }
        func setWish(_ text: String?, for day: String) {
            let cleaned = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            stored[day] = cleaned.isEmpty ? nil : cleaned
        }
    }

    private final class Authorizer: HealthDataAuthorizing {
        var error: Error?
        func requestAuthorization() async throws {
            if let error { throw error }
        }
    }

    private func makeLoader(
        cache: MemoryCache = MemoryCache(),
        history: DayPlanV2HistoryStoring? = nil,
        wishes: DailyWishStoring? = nil,
        dayTarget: @escaping @MainActor () -> DayTargetV2? = { nil },
        equipment: @escaping @MainActor () -> [String]? = { nil },
        recentTraining: @escaping @MainActor (AthleteStateReading) -> [RecentTrainingEntry] = { _ in [] },
        testSettings: @escaping @MainActor () -> TestSettings? = { nil },
        prepare: @escaping @MainActor (AthleteStateReading) async -> Void = { _ in },
        previewStore: DayPlanPreviewStoring? = nil,
        targetOn: @escaping @MainActor (String) -> DayTargetV2? = { _ in nil },
        extrasOn: @escaping @MainActor (String) -> PlanningExtras = { _ in .none },
        adoptPlan: @escaping @MainActor (DayPlanV2Response) -> DayTargetV2? = { _ in nil },
        provider: CountingProvider?,
        repository: FakeAllSportsRepository = FakeAllSportsRepository(workouts: TodayLoaderV2Data.workouts),
        authorizer: Authorizer = Authorizer()
    ) -> MultiSportTodayLoader {
        MultiSportTodayLoader(
            authorizer: authorizer,
            snapshotBuilder: SnapshotBuilder(
                repository: repository,
                vitalsRepository: FakeVitalsRepository(),
                trainingGoalProvider: { TrainingGoal.default },
                calendar: TestFixtures.utc
            ),
            planProvider: { provider },
            cache: cache,
            history: history,
            wishStore: wishes,
            dayTarget: dayTarget,
            equipment: equipment,
            recentTraining: recentTraining,
            testSettings: testSettings,
            prepare: prepare,
            previewStore: previewStore,
            targetOn: targetOn,
            extrasOn: extrasOn,
            adoptPlan: adoptPlan,
            now: { TestFixtures.now },
            calendar: TestFixtures.utc
        )
    }

    // MARK: - Ein Tag im Plan-Tab

    private final class MemoryPreviews: DayPlanPreviewStoring {
        var stored: [DayPlanV2Response]
        init(_ stored: [DayPlanV2Response] = []) { self.stored = stored }
        func load() -> [DayPlanV2Response] { stored }
        func save(_ previews: [DayPlanV2Response]) throws { stored = previews }
    }

    private static let friday = DayTargetV2(focus: "Locker", sessions: [
        DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .easy, amount: 40, focus: "Locker")
    ])

    func testAComingDayGetsAPreviewWithItsDateAndKeepsIt() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response(date: "2026-10-02")))
        let store = MemoryPreviews([TodayLoaderV2Data.response(date: "2026-09-28")])
        var target: DayTargetV2? = Self.friday
        let loader = makeLoader(
            previewStore: store,
            targetOn: { date in date == "2026-10-02" ? target : nil },
            extrasOn: { date in PlanningExtras(availability: [DayAvailability(date: date, minutes: 50)]) },
            provider: provider
        )
        // Vergangene Vorschauen fallen beim Start weg.
        XCTAssertTrue(loader.previews.isEmpty)
        await loader.readHealth()

        XCTAssertTrue(loader.canPreview("2026-10-02"))
        XCTAssertFalse(loader.canPreview("2026-10-03"), "ohne Einheiten keine Vorschau")
        XCTAssertFalse(loader.canPreview("2026-09-30"), "heute plant der Tab Heute")
        XCTAssertNil(loader.dayPlan(on: "2026-10-02"))

        await loader.loadPreview(for: "2026-10-02")

        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertEqual(request.date, "2026-10-02")
        XCTAssertEqual(request.dayPlan, Self.friday)
        XCTAssertEqual(request.extras.availableMinutes(on: "2026-10-02"), 50)
        XCTAssertEqual(loader.dayPlan(on: "2026-10-02")?.date, "2026-10-02")
        XCTAssertEqual(store.stored.map(\.date), ["2026-10-02"])
        XCTAssertNil(loader.response, "Die Vorschau ersetzt nicht den Plan von heute")

        // Nach einer Änderung an dem Tag passt die Vorschau nicht mehr.
        target = DayTargetV2(focus: "Rad", sessions: [DayTargetV2.Session(sport: .bike, sessionType: .endurance, intensity: .easy, amount: 60, focus: "Rad")])
        XCTAssertNil(loader.dayPlan(on: "2026-10-02"))
    }

    func testTodayAndPastDaysShowTheirPlans() async throws {
        let yesterday = TodayLoaderV2Data.response(date: "2026-09-29")
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(history: MemoryHistory([yesterday]), provider: provider)

        XCTAssertEqual(loader.dayPlan(on: "2026-09-29"), yesterday)
        XCTAssertNil(loader.dayPlan(on: "2026-09-28"))

        await loader.refreshIfNeeded()
        XCTAssertEqual(loader.dayPlan(on: "2026-09-30")?.date, "2026-09-30")
    }

    // MARK: - Abgleich mit dem Plan-Tab

    func testAChangeInThePlanTabGetsANewPlanAtOnce() async throws {
        let swim = DayTargetV2(focus: "Technik", sessions: [DayTargetV2.Session(sport: .swim, sessionType: .technique, intensity: .easy, amount: 1_500, focus: "Technik")])
        let run = DayTargetV2(focus: "Locker", sessions: [DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .easy, amount: 30, focus: "Locker")])
        var target: DayTargetV2? = swim
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(dayTarget: { target }, provider: provider)
        await loader.refreshIfNeeded()
        XCTAssertEqual(provider.calls, 1)

        // Unverändert: nichts zu tun.
        await loader.syncWithTodayTarget()
        XCTAssertEqual(provider.calls, 1)

        target = run
        XCTAssertFalse(loader.matchesTodayTarget)
        XCTAssertNil(loader.dayPlan(on: "2026-09-30"), "Der alte Plan gilt nicht mehr")
        await loader.syncWithTodayTarget()

        XCTAssertEqual(provider.calls, 2)
        XCTAssertEqual(provider.requests.last?.dayPlan, run)
        XCTAssertTrue(loader.matchesTodayTarget)
        XCTAssertNotNil(loader.dayPlan(on: "2026-09-30"))
    }

    func testARestDayInThePlanTabNeedsNoCall() async throws {
        let swim = DayTargetV2(focus: "Technik", sessions: [DayTargetV2.Session(sport: .swim, sessionType: .technique, intensity: .easy, amount: 1_500, focus: "Technik")])
        var target: DayTargetV2? = swim
        let cache = MemoryCache()
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(cache: cache, dayTarget: { target }, provider: provider)
        await loader.refreshIfNeeded()

        target = DayTargetV2(focus: "Keine Zeit", sessions: [])
        await loader.syncWithTodayTarget()

        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(loader.response?.plan.isRestDay, true)
        XCTAssertTrue(loader.matchesTodayTarget)
        XCTAssertEqual(cache.stored?.plan.isRestDay, true)
    }

    func testANewDayPlanIsHandedToTheWeekAndKeepsMatching() async throws {
        let swim = DayTargetV2(focus: "Technik", sessions: [DayTargetV2.Session(sport: .swim, sessionType: .technique, intensity: .easy, amount: 1_500, focus: "Technik")])
        let adopted = DayTargetV2(focus: "Technik + Locker", sessions: [
            DayTargetV2.Session(sport: .swim, sessionType: .technique, intensity: .easy, amount: 1_500, focus: "Technik"),
            DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .easy, amount: 30, focus: "Locker")
        ])
        var target: DayTargetV2? = swim
        var handed: [DayPlanV2Response] = []
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(dayTarget: { target }, adoptPlan: { response in
            handed.append(response)
            target = adopted
            return adopted
        }, provider: provider)

        await loader.refreshIfNeeded()

        XCTAssertEqual(handed.count, 1)
        XCTAssertEqual(loader.response?.requestedTarget, adopted)
        XCTAssertTrue(loader.matchesTodayTarget, "Nach dem Übernehmen passt der Plan zur Woche")
        await loader.refreshIfNeeded()
        XCTAssertEqual(provider.calls, 1)
    }

    // MARK: - Synchronisierung nach Entscheidung

    func testAChangeDuringARunningRequestWinsOverTheOldAnswer() async throws {
        let swim = DayTargetV2(focus: "Technik", sessions: [DayTargetV2.Session(sport: .swim, sessionType: .technique, intensity: .easy, amount: 1_500, focus: "Technik")])
        let run = DayTargetV2(focus: "Locker", sessions: [DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .easy, amount: 30, focus: "Locker")])
        var target: DayTargetV2? = swim
        var adopted: [DayTargetV2?] = []
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        // Während die erste Anfrage (Schwimmen) läuft, ändert der Athlet heute auf Laufen.
        provider.whileFetching = { call in if call == 1 { target = run } }
        let loader = makeLoader(dayTarget: { target }, adoptPlan: { response in
            adopted.append(target)
            return target
        }, provider: provider)

        await loader.refreshIfNeeded()

        // Die Antwort für Schwimmen wird verworfen, nicht übernommen; danach wird für Laufen gefragt.
        XCTAssertEqual(provider.requests.map(\.dayPlan), [swim, run])
        XCTAssertEqual(adopted, [run])
        XCTAssertEqual(loader.response?.requestedTarget, run)
        XCTAssertTrue(loader.matchesTodayTarget)
    }

    func testSeveralChangesInARowGiveOneRequest() async throws {
        var target: DayTargetV2? = DayTargetV2(focus: "A", sessions: [DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .easy, amount: 30, focus: "A")])
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(dayTarget: { target }, provider: provider)
        await loader.refreshIfNeeded()

        for amount in [35.0, 40, 45] {
            target = DayTargetV2(focus: "A", sessions: [DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .easy, amount: amount, focus: "A")])
            loader.scheduleSync(after: 0.05)
        }
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(provider.calls, 2)
        XCTAssertEqual(provider.requests.last?.dayPlan?.sessions.first?.amount, 45)
    }

    func testAFallbackPlanIsShownButDoesNotCountAsMatching() async throws {
        let target = DayTargetV2(focus: "Locker", sessions: [DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .easy, amount: 30, focus: "Locker")])
        var adopted = 0
        let provider = CountingProvider(.success(TodayLoaderV2Data.response(source: .fallback)))
        let loader = makeLoader(dayTarget: { target }, adoptPlan: { _ in adopted += 1; return target }, provider: provider)

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.response?.source, .fallback)
        XCTAssertNil(loader.response?.requestedTarget)
        XCTAssertFalse(loader.matchesTodayTarget)
        XCTAssertEqual(adopted, 0, "Ein Ersatzplan kommt nicht in die Woche")
        XCTAssertNil(loader.dayPlan(on: "2026-09-30"))
    }

    func testThePreviewBecomesTodaysPlanWithoutACall() async throws {
        let target = DayTargetV2(focus: "Locker", sessions: [DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .easy, amount: 30, focus: "Locker")])
        var preview = TodayLoaderV2Data.response(date: "2026-09-30")
        preview.requestedTarget = target
        let history = MemoryHistory()
        let previews = MemoryPreviews([preview])
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        // Gestern als Vorschau geholt: Der Lader startet heute (Vorschauen von heute bleiben beim Start).
        let loader = makeLoader(history: history, dayTarget: { target }, previewStore: previews, provider: provider)

        XCTAssertTrue(loader.isTodayLocked, "Eine Vorschau für heute hält heute fest")
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(loader.response, preview)
        XCTAssertEqual(history.stored.map(\.date), ["2026-09-30"])
        XCTAssertTrue(previews.stored.isEmpty)
        XCTAssertTrue(loader.isTodayLocked)
    }

    func testTheHistoryKeepsTheLastPlanOfTheDay() async throws {
        let history = MemoryHistory()
        var target: DayTargetV2? = DayTargetV2(focus: "A", sessions: [DayTargetV2.Session(sport: .swim, sessionType: .endurance, intensity: .easy, amount: 1_500, focus: "A")])
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(history: history, dayTarget: { target }, provider: provider)
        await loader.refreshIfNeeded()

        target = DayTargetV2(focus: "Ruhetag", sessions: [])
        await loader.syncWithTodayTarget()

        XCTAssertEqual(history.stored.count, 1)
        XCTAssertEqual(history.stored.first?.plan.isRestDay, true)
    }

    func testAFailedPreviewKeepsTheErrorForItsDay() async throws {
        let provider = CountingProvider(.failure(PlanAPIError.server(status: 503)))
        let loader = makeLoader(targetOn: { _ in Self.friday }, provider: provider)
        await loader.readHealth()

        await loader.loadPreview(for: "2026-10-01")

        XCTAssertEqual(loader.previewError?.date, "2026-10-01")
        XCTAssertNil(loader.dayPlan(on: "2026-10-01"))
        XCTAssertNil(loader.loadingPreviewDate)
        XCTAssertFalse(loader.canPreview("2026-10-20"), "weiter als der Server vorausplant")
    }

    func testReadHealthOnlyReadsTheState() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        var prepared = 0
        let loader = makeLoader(prepare: { _ in prepared += 1 }, provider: provider)

        await loader.readHealth()

        XCTAssertNotNil(loader.reading)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(prepared, 0)
        XCTAssertFalse(loader.isLoading)
    }

    func testPullToRefreshNeverFetchesOrPreparesAPlan() async throws {
        let cache = MemoryCache(TodayLoaderV2Data.response(date: "2026-09-29"))
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        var prepared = 0
        let loader = makeLoader(cache: cache, prepare: { _ in prepared += 1 }, provider: provider)

        await loader.pullToRefresh()

        XCTAssertNotNil(loader.reading)
        XCTAssertEqual(provider.calls, 0, "auch ohne Plan von heute kein Claude-Aufruf")
        XCTAssertEqual(prepared, 0, "Gesamtplan und sieben Tage bleiben")
        XCTAssertEqual(loader.response?.date, "2026-09-29")
    }

    // MARK: - Plan holen

    func testFetchesAndCachesAPlanWhenNoneIsThereForToday() async throws {
        let cache = MemoryCache(TodayLoaderV2Data.response(date: "2026-09-29"))
        let fresh = TodayLoaderV2Data.response()
        let provider = CountingProvider(.success(fresh))
        let loader = makeLoader(cache: cache, provider: provider)

        XCTAssertFalse(loader.hasFreshPlanForToday)
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(provider.newPlanCalls, 0)
        XCTAssertEqual(loader.response, fresh)
        XCTAssertEqual(cache.stored, fresh)
        XCTAssertEqual(cache.saves, 1)
        XCTAssertTrue(loader.hasFreshPlanForToday)
        XCTAssertEqual(loader.reading?.allWorkouts.count, 2)
        XCTAssertNil(loader.planError)
        XCTAssertNil(loader.healthError)
        XCTAssertFalse(loader.needsConfiguration)
        XCTAssertFalse(loader.isLoading)
    }

    func testDoesNotCallTheServerOnOpenWhenTodaysPlanIsCached() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(cache: MemoryCache(TodayLoaderV2Data.response()), provider: provider)

        XCTAssertTrue(loader.hasFreshPlanForToday)
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 0)
        // Health wird trotzdem neu gelesen.
        XCTAssertNotNil(loader.reading)
    }

    func testOpeningAgainOnTheSameDayAsksTheServerOnlyOnce() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(provider: provider)

        await loader.refreshIfNeeded()
        await loader.refreshIfNeeded()
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 1)
    }

    func testAFallbackPlanIsRetriedOnOpen() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(cache: MemoryCache(TodayLoaderV2Data.response(source: .fallback)), provider: provider)

        XCTAssertFalse(loader.hasFreshPlanForToday)
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(loader.response?.source, .claude)
    }

    func testPullAsksForANewPlanButOpeningDoesNot() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(cache: MemoryCache(TodayLoaderV2Data.response()), provider: provider)

        await loader.refreshIfNeeded()
        XCTAssertEqual(provider.calls, 0)

        await loader.refresh()
        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(provider.newPlanCalls, 1)
    }

    func testTheRequestCarriesTargetEquipmentRecentTrainingAndTestSettings() async throws {
        let target = DayTargetV2(focus: "Radtest", sessions: [
            DayTargetV2.Session(sport: .bike, sessionType: .test, intensity: .hard, amount: 58, focus: "30-Minuten-Test", testID: "threshold_30min")
        ])
        let entries = [RecentTrainingEntry(date: "2026-09-29", sport: .swim, minutes: 30, meters: 1_500, hard: false)]
        let settings = TestSettings(offer: true, intervalWeeks: 8)
        var received: AthleteStateReading?
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(
            dayTarget: { target },
            equipment: { ["pull_buoy"] },
            recentTraining: { reading in
                received = reading
                return entries
            },
            testSettings: { settings },
            provider: provider
        )

        await loader.refresh()

        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertTrue(request.regenerate)
        XCTAssertNil(request.wishes)
        XCTAssertEqual(request.dayPlan, target)
        XCTAssertEqual(request.equipment, ["pull_buoy"])
        XCTAssertEqual(request.recentTraining, entries)
        XCTAssertEqual(request.testSettings, settings)
        XCTAssertEqual(request.snapshot, loader.reading?.snapshot)
        // Das bisherige Training kommt aus dem frisch gelesenen Zustand.
        XCTAssertNotNil(received)
        XCTAssertEqual(received, loader.reading)
    }

    func testWithoutSettingsNothingOptionalIsSent() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(provider: provider)

        await loader.refresh()

        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertNil(request.dayPlan)
        XCTAssertNil(request.equipment)
        XCTAssertNil(request.testSettings)
        XCTAssertEqual(request.recentTraining, [])
    }

    func testTheTargetIsReadAtRequestTimeSoChangesToTheWeekCount() async throws {
        var target: DayTargetV2? = DayTargetV2(focus: "Laufen", sessions: [
            DayTargetV2.Session(sport: .run, sessionType: .endurance, intensity: .easy, amount: 40, focus: "Locker")
        ])
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(dayTarget: { target }, provider: provider)
        await loader.refresh()

        target = nil
        await loader.refresh()

        XCTAssertEqual(provider.requests.map(\.dayPlan?.focus), ["Laufen", nil])
    }

    // MARK: - Vorgabe für heute

    private static func swimTarget(_ meters: Double) -> DayTargetV2 {
        DayTargetV2(focus: "Schwimmen", sessions: [
            DayTargetV2.Session(sport: .swim, sessionType: .endurance, intensity: .easy, amount: meters, focus: "Locker")
        ])
    }

    func testAChangedTargetForTodayFetchesANewPlanOnOpen() async throws {
        var target = Self.swimTarget(1_500)
        let cache = MemoryCache()
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(cache: cache, dayTarget: { target }, provider: provider)

        await loader.refreshIfNeeded()
        await loader.refreshIfNeeded()
        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(cache.stored?.requestedTarget, target)
        XCTAssertTrue(loader.matchesTodayTarget)

        // Im Plan-Tab: heute 2000 statt 1500 m Schwimmen.
        target = Self.swimTarget(2_000)
        XCTAssertFalse(loader.matchesTodayTarget)
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 2)
        // Kein "neu würfeln": Mit der neuen Vorgabe erzeugt der Server ohnehin einen neuen Plan.
        XCTAssertEqual(provider.newPlanCalls, 0)
        XCTAssertEqual(provider.requests.last?.dayPlan, Self.swimTarget(2_000))
        XCTAssertEqual(loader.response?.requestedTarget, Self.swimTarget(2_000))
        XCTAssertEqual(cache.stored?.requestedTarget, Self.swimTarget(2_000))
        XCTAssertTrue(loader.matchesTodayTarget)

        await loader.refreshIfNeeded()
        XCTAssertEqual(provider.calls, 2)
    }

    func testATargetChangedWhilePreparingIsFollowedRightAway() async throws {
        var target: DayTargetV2? = Self.swimTarget(1_500)
        var cached = TodayLoaderV2Data.response()
        cached.requestedTarget = target
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(
            cache: MemoryCache(cached),
            dayTarget: { target },
            // Die sieben Tage werden neu geplant, heute ist jetzt Rad dran.
            prepare: { _ in target = DayTargetV2(focus: "Rad", sessions: [
                DayTargetV2.Session(sport: .bike, sessionType: .endurance, intensity: .easy, amount: 60, focus: "Locker")
            ]) },
            provider: provider
        )

        XCTAssertTrue(loader.matchesTodayTarget)
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(provider.requests.first?.dayPlan?.focus, "Rad")
    }

    func testACachedPlanWithoutTargetIsFetchedAgainWhenTheWeekHasOne() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(cache: MemoryCache(TodayLoaderV2Data.response()), dayTarget: { Self.swimTarget(1_500) }, provider: provider)

        XCTAssertTrue(loader.hasFreshPlanForToday)
        XCTAssertFalse(loader.matchesTodayTarget)
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 1)
    }

    // MARK: - Vorbereiten

    func testThePlanIsPreparedWithTheFreshReadingBeforeTheDayPlanIsFetched() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        var events: [String] = []
        var preparedWith: AthleteStateReading?
        let loader = makeLoader(
            prepare: { reading in
                events.append("prepare (Pläne bisher: \(provider.calls))")
                preparedWith = reading
            },
            provider: provider
        )

        await loader.refreshIfNeeded()

        XCTAssertEqual(events, ["prepare (Pläne bisher: 0)"])
        XCTAssertEqual(preparedWith, loader.reading)
        XCTAssertEqual(provider.calls, 1)
        XCTAssertFalse(loader.isPreparing)
        XCTAssertFalse(loader.isLoading)
    }

    func testThePlanIsPreparedEvenWhenTodaysPlanIsCached() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        var prepared = 0
        let loader = makeLoader(cache: MemoryCache(TodayLoaderV2Data.response()), prepare: { _ in prepared += 1 }, provider: provider)

        await loader.refreshIfNeeded()

        XCTAssertEqual(prepared, 1)
        XCTAssertEqual(provider.calls, 0)
    }

    func testNothingIsPreparedWhenHealthCannotBeRead() async throws {
        let authorizer = Authorizer()
        authorizer.error = TestError(message: "nicht verfügbar")
        var prepared = 0
        let loader = makeLoader(
            prepare: { _ in prepared += 1 },
            provider: CountingProvider(.success(TodayLoaderV2Data.response())),
            authorizer: authorizer
        )

        await loader.refreshIfNeeded()

        XCTAssertEqual(prepared, 0)
    }

    // MARK: - Fehler

    func testAServerErrorKeepsTheCachedPlan() async throws {
        let cached = TodayLoaderV2Data.response(date: "2026-09-29")
        let loader = makeLoader(
            cache: MemoryCache(cached),
            provider: CountingProvider(.failure(PlanAPIError.planUnavailable(reason: "timeout")))
        )

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.response, cached)
        XCTAssertEqual(loader.planError, PlanAPIError.planUnavailable(reason: "timeout").errorDescription)
        XCTAssertFalse(loader.isLoadingPlan)
    }

    func testASuccessfulFetchClearsAnEarlierPlanError() async throws {
        let provider = CountingProvider(.failure(TestError(message: "offline")))
        let loader = makeLoader(provider: provider)
        await loader.refresh()
        XCTAssertEqual(loader.planError, "offline")
        XCTAssertNil(loader.response)

        provider.result = .success(TodayLoaderV2Data.response())
        await loader.refresh()

        XCTAssertNil(loader.planError)
        XCTAssertEqual(loader.response, TodayLoaderV2Data.response())
    }

    func testWithoutATokenItAsksForConfiguration() async throws {
        let loader = makeLoader(provider: nil)

        await loader.refreshIfNeeded()

        XCTAssertTrue(loader.needsConfiguration)
        XCTAssertNil(loader.response)
        XCTAssertNotNil(loader.reading)
        XCTAssertNil(loader.planError)
    }

    func testAHealthFailureSkipsTheServer() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(provider: provider, repository: FakeAllSportsRepository(error: TestError(message: "Health gesperrt")))

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.healthError, "Health gesperrt")
        XCTAssertNil(loader.reading)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertFalse(loader.isLoadingHealth)
    }

    func testADeniedAuthorizationIsReported() async throws {
        let authorizer = Authorizer()
        authorizer.error = TestError(message: "nicht verfügbar")
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(provider: provider, authorizer: authorizer)

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.healthError, "nicht verfügbar")
        XCTAssertNil(loader.reading)
        XCTAssertEqual(provider.calls, 0)
    }

    // MARK: - Verlauf

    func testAFreshPlanIsRecordedInTheHistory() async throws {
        let history = MemoryHistory()
        let fresh = TodayLoaderV2Data.response()
        let loader = makeLoader(history: history, provider: CountingProvider(.success(fresh)))

        XCTAssertTrue(loader.planHistory.isEmpty)
        await loader.refreshIfNeeded()

        XCTAssertEqual(history.stored, [fresh])
        XCTAssertEqual(loader.planHistory, [fresh])
    }

    func testACachedPlanFromBeforeTheHistoryIsAdopted() {
        let cached = TodayLoaderV2Data.response(date: "2026-09-29")
        let history = MemoryHistory()
        let loader = makeLoader(cache: MemoryCache(cached), history: history, provider: nil)

        XCTAssertEqual(history.stored, [cached])
        XCTAssertEqual(loader.planHistory, [cached])
    }

    func testAFailedFetchLeavesTheHistoryUntouched() async throws {
        let history = MemoryHistory([TodayLoaderV2Data.response(date: "2026-09-29")])
        let loader = makeLoader(history: history, provider: CountingProvider(.failure(TestError(message: "offline"))))

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.planHistory.map(\.date), ["2026-09-29"])
    }

    func testTheLoaderWorksWithoutHistory() async throws {
        let loader = makeLoader(provider: CountingProvider(.success(TodayLoaderV2Data.response())))

        await loader.refreshIfNeeded()

        XCTAssertTrue(loader.planHistory.isEmpty)
        XCTAssertNotNil(loader.response)
    }

    // MARK: - Wunsch für heute

    func testTheWishGoesWithEveryRequestOfTheDay() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(wishes: MemoryWishes(["2026-09-30": "Heute lieber Rad"]), provider: provider)

        XCTAssertEqual(loader.wish, "Heute lieber Rad")
        await loader.refresh()

        XCTAssertEqual(provider.requests.first?.wishes, "Heute lieber Rad")
        XCTAssertEqual(provider.requests.first?.regenerate, true)
    }

    func testReplanSavesTheWishAndAsksForANewPlan() async throws {
        let wishes = MemoryWishes()
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(wishes: wishes, provider: provider)

        await loader.replan(withWish: "  Schulter zwickt  ")

        XCTAssertEqual(wishes.stored, ["2026-09-30": "Schulter zwickt"])
        XCTAssertEqual(loader.wish, "Schulter zwickt")
        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(provider.requests.first?.wishes, "Schulter zwickt")
        XCTAssertEqual(provider.requests.first?.regenerate, true)
    }

    func testAnEmptyWishRemovesItAndIsNotSent() async throws {
        let wishes = MemoryWishes(["2026-09-30": "alt"])
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(wishes: wishes, provider: provider)

        await loader.replan(withWish: "   ")

        XCTAssertEqual(loader.wish, "")
        XCTAssertTrue(wishes.stored.isEmpty)
        XCTAssertEqual(provider.calls, 1)
        XCTAssertNil(provider.requests.first?.wishes)
    }

    func testYesterdaysWishDoesNotApplyToday() async throws {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(wishes: MemoryWishes(["2026-09-29": "gestern"]), provider: provider)

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.wish, "")
        XCTAssertEqual(provider.calls, 1)
        XCTAssertNil(provider.requests.first?.wishes)
        XCTAssertEqual(provider.requests.first?.regenerate, false)
    }

    func testSavingAWishAloneDoesNotCallTheServer() {
        let provider = CountingProvider(.success(TodayLoaderV2Data.response()))
        let loader = makeLoader(wishes: MemoryWishes(), provider: provider)

        loader.setWish("mehr Ausdauer")

        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(loader.wish, "mehr Ausdauer")
    }
}
