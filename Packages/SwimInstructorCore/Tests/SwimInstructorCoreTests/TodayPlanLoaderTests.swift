import XCTest
@testable import SwimInstructorCore

@MainActor
final class TodayPlanLoaderTests: XCTestCase {
    private final class MemoryCache: PlanCaching {
        var stored: PlanResponse?
        init(_ stored: PlanResponse? = nil) { self.stored = stored }
        func load() -> PlanResponse? { stored }
        func save(_ response: PlanResponse) throws { stored = response }
    }

    private final class MemoryHistory: PlanHistoryStoring {
        var stored: [PlanResponse]
        init(_ stored: [PlanResponse] = []) { self.stored = stored }
        func load() -> [PlanResponse] { stored }
        func record(_ response: PlanResponse) throws {
            guard response.source != .fallback, !stored.contains(where: { $0.date == response.date }) else { return }
            stored.append(response)
        }
    }

    private final class CountingProvider: PlanProviding, @unchecked Sendable {
        let result: Result<PlanResponse, Error>
        private(set) var calls = 0
        private(set) var newPlanCalls = 0
        init(_ result: Result<PlanResponse, Error>) { self.result = result }
        func fetchTodayPlan(for snapshot: AthleteStateSnapshot) async throws -> PlanResponse {
            calls += 1
            return try result.get()
        }
        func fetchNewPlan(for snapshot: AthleteStateSnapshot) async throws -> PlanResponse {
            calls += 1
            newPlanCalls += 1
            return try result.get()
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
        history: PlanHistoryStoring? = nil,
        provider: CountingProvider?,
        workouts: FakeWorkoutRepository = FakeWorkoutRepository(workouts: [TestFixtures.workout(daysAgo: 1, meters: 1500)]),
        authorizer: Authorizer = Authorizer()
    ) -> TodayPlanLoader {
        TodayPlanLoader(
            authorizer: authorizer,
            snapshotBuilder: SnapshotBuilder(
                workoutRepository: workouts,
                vitalsRepository: FakeVitalsRepository(),
                calendar: TestFixtures.utc
            ),
            planProvider: { provider },
            cache: cache,
            history: history,
            now: { TestFixtures.now },
            calendar: TestFixtures.utc
        )
    }

    func testFetchesAndCachesPlanWhenNoneForToday() async {
        let cache = MemoryCache(TestFixtures.response(date: "2026-09-29"))
        let fresh = TestFixtures.response()
        let provider = CountingProvider(.success(fresh))
        let loader = makeLoader(cache: cache, provider: provider)

        XCTAssertFalse(loader.hasFreshPlanForToday)
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(loader.response, fresh)
        XCTAssertEqual(cache.stored, fresh)
        XCTAssertEqual(loader.reading?.workouts.count, 1)
        XCTAssertNil(loader.planError)
        XCTAssertFalse(loader.isLoading)
    }

    func testDoesNotCallServerOnOpenWhenTodaysPlanIsCached() async {
        let provider = CountingProvider(.success(TestFixtures.response()))
        let loader = makeLoader(cache: MemoryCache(TestFixtures.response()), provider: provider)

        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 0)
        // Die Einheiten aus Health werden trotzdem neu gelesen.
        XCTAssertNotNil(loader.reading)
    }

    func testManualRefreshAlwaysAsksServer() async {
        let provider = CountingProvider(.success(TestFixtures.response()))
        let loader = makeLoader(cache: MemoryCache(TestFixtures.response()), provider: provider)

        await loader.refresh()

        XCTAssertEqual(provider.calls, 1)
    }

    func testPullAsksForANewPlanButOpeningDoesNot() async {
        let provider = CountingProvider(.success(TestFixtures.response()))
        let loader = makeLoader(provider: provider)

        await loader.refreshIfNeeded()
        XCTAssertEqual(provider.newPlanCalls, 0)

        await loader.refresh()
        XCTAssertEqual(provider.newPlanCalls, 1)
    }

    func testOpeningTheAppAgainOnTheSameDayDoesNotAskTheServer() async {
        let provider = CountingProvider(.success(TestFixtures.response()))
        let loader = makeLoader(provider: provider)

        await loader.refreshIfNeeded()
        await loader.refreshIfNeeded()
        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 1)
    }

    func testFallbackPlanIsRetriedOnOpen() async {
        let provider = CountingProvider(.success(TestFixtures.response()))
        let loader = makeLoader(cache: MemoryCache(TestFixtures.response(source: .fallback)), provider: provider)

        await loader.refreshIfNeeded()

        XCTAssertEqual(provider.calls, 1)
        XCTAssertEqual(loader.response?.source, .claude)
    }

    func testServerErrorKeepsCachedPlan() async {
        let cached = TestFixtures.response(date: "2026-09-29")
        let loader = makeLoader(
            cache: MemoryCache(cached),
            provider: CountingProvider(.failure(PlanAPIError.planUnavailable(reason: "timeout")))
        )

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.response, cached)
        XCTAssertEqual(loader.planError, PlanAPIError.planUnavailable(reason: "timeout").errorDescription)
    }

    func testWithoutTokenAsksForConfiguration() async {
        let loader = makeLoader(provider: nil)

        await loader.refreshIfNeeded()

        XCTAssertTrue(loader.needsConfiguration)
        XCTAssertNil(loader.response)
        XCTAssertNotNil(loader.reading)
    }

    func testHealthFailureSkipsServer() async {
        let provider = CountingProvider(.success(TestFixtures.response()))
        let loader = makeLoader(
            provider: provider,
            workouts: FakeWorkoutRepository(error: TestError(message: "Health gesperrt"))
        )

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.healthError, "Health gesperrt")
        XCTAssertEqual(provider.calls, 0)
    }

    func testDeniedAuthorizationIsReported() async {
        let authorizer = Authorizer()
        authorizer.error = TestError(message: "nicht verfügbar")
        let loader = makeLoader(provider: CountingProvider(.success(TestFixtures.response())), authorizer: authorizer)

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.healthError, "nicht verfügbar")
        XCTAssertNil(loader.reading)
    }

    func testFreshPlanIsRecordedInHistory() async {
        let history = MemoryHistory()
        let fresh = TestFixtures.response()
        let loader = makeLoader(history: history, provider: CountingProvider(.success(fresh)))

        XCTAssertTrue(loader.planHistory.isEmpty)
        await loader.refreshIfNeeded()

        XCTAssertEqual(history.stored, [fresh])
        XCTAssertEqual(loader.planHistory, [fresh])
    }

    func testCachedPlanFromBeforeHistoryExistedIsAdopted() {
        let cached = TestFixtures.response(date: "2026-09-29")
        let history = MemoryHistory()
        let loader = makeLoader(cache: MemoryCache(cached), history: history, provider: nil)

        XCTAssertEqual(history.stored, [cached])
        XCTAssertEqual(loader.planHistory, [cached])
    }

    func testFailedFetchLeavesHistoryUntouched() async {
        let history = MemoryHistory([TestFixtures.response(date: "2026-09-29")])
        let loader = makeLoader(
            history: history,
            provider: CountingProvider(.failure(TestError(message: "offline")))
        )

        await loader.refreshIfNeeded()

        XCTAssertEqual(loader.planHistory.map(\.date), ["2026-09-29"])
    }

    func testLoaderWorksWithoutHistory() async {
        let loader = makeLoader(provider: CountingProvider(.success(TestFixtures.response())))

        await loader.refreshIfNeeded()

        XCTAssertTrue(loader.planHistory.isEmpty)
        XCTAssertNotNil(loader.response)
    }
}
