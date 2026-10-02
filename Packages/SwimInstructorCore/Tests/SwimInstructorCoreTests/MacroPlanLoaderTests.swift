import XCTest
@testable import SwimInstructorCore

@MainActor
final class MacroPlanLoaderTests: XCTestCase {
    private final class MemoryStore: MacroPlanStoring {
        var stored: MacroPlan?
        private(set) var saves = 0
        init(_ stored: MacroPlan? = nil) { self.stored = stored }
        func load() -> MacroPlan? { stored }
        func save(_ plan: MacroPlan) throws {
            stored = plan
            saves += 1
        }
    }

    private final class FakeProvider: MacroPlanProviding, @unchecked Sendable {
        private(set) var requests: [MacroPlanRequest] = []
        let failure: Error?
        init(failure: Error? = nil) { self.failure = failure }

        func fetchMacroPlan(_ request: MacroPlanRequest) async throws -> MacroPlanResponse {
            requests.append(request)
            if let failure { throw failure }
            return try PlanResponse.jsonDecoder().decode(MacroPlanResponse.self, from: Data(MacroFixtures.responseJSON.utf8))
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
        goal: @escaping @MainActor () -> AthleteGoal = { .default },
        marker: MemoryMarker = MemoryMarker()
    ) -> MacroPlanLoader {
        MacroPlanLoader(
            store: store,
            planProvider: { provider },
            goal: goal,
            attemptMarker: marker,
            now: { TestFixtures.now },
            calendar: TestFixtures.utc
        )
    }

    func testLoadsTheStoredPlan() {
        let loader = makeLoader(store: MemoryStore(MacroFixtures.plan()), provider: nil)

        XCTAssertEqual(loader.plan, MacroFixtures.plan())
        XCTAssertEqual(loader.currentWeek?.targetMeters, 3500)
        XCTAssertEqual(loader.todayKey, "2026-09-30")
        XCTAssertEqual(loader.currentWeekStart, "2026-09-28")
    }

    func testThePlanIsCurrentOnlyForTheSameGoalAndWithTheRunningWeek() {
        XCTAssertTrue(makeLoader(store: MemoryStore(MacroFixtures.plan()), provider: nil).isCurrent)
        XCTAssertFalse(makeLoader(provider: nil).isCurrent)
        XCTAssertFalse(makeLoader(store: MemoryStore(MacroFixtures.plan(goalKey: "anderes-ziel")), provider: nil).isCurrent)
        // Abgelaufen: die laufende Woche fehlt.
        XCTAssertFalse(makeLoader(store: MemoryStore(MacroFixtures.plan(weeks: [MacroFixtures.week("2026-10-05")])), provider: nil).isCurrent)
    }

    func testEnsureCurrentFetchesAStoresAndMarksThePlanWhenNoneExists() async {
        let store = MemoryStore()
        let provider = FakeProvider()
        let loader = makeLoader(store: store, provider: provider)

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(provider.requests.first?.today, "2026-09-30")
        XCTAssertEqual(provider.requests.first?.snapshot, TestFixtures.snapshot)
        XCTAssertEqual(loader.plan?.goalKey, MacroFixtures.goalKey)
        XCTAssertEqual(loader.plan?.weeks.count, 5)
        XCTAssertEqual(store.saves, 1)
        XCTAssertNil(loader.error)
        XCTAssertFalse(loader.isLoading)
    }

    func testEnsureCurrentDoesNothingWhileThePlanIsCurrent() async {
        let provider = FakeProvider()
        let loader = makeLoader(store: MemoryStore(MacroFixtures.plan()), provider: provider)

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testEnsureCurrentTriesOnlyOncePerDayEvenAfterAFailure() async {
        let provider = FakeProvider(failure: PlanAPIError.network("aus"))
        let loader = makeLoader(provider: provider)

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)
        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)
        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertNotNil(loader.error)
        XCTAssertNil(loader.plan)
    }

    func testAChangedGoalIsReplannedEvenOnTheSameDay() async {
        var goal = AthleteGoal.default
        let provider = FakeProvider()
        let store = MemoryStore(MacroFixtures.plan())
        let loader = makeLoader(store: store, provider: provider, goal: { goal })

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)
        XCTAssertTrue(provider.requests.isEmpty)

        goal = AthleteGoal(distanceMeters: 1500, targetDurationSeconds: 1680, targetDate: AthleteGoal.default.targetDate)
        XCTAssertFalse(loader.isCurrent)
        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(loader.plan?.goalKey, "1500-1680-2027-07-04")
        XCTAssertTrue(loader.isCurrent)
    }

    func testAFailedRegenerationKeepsTheOldPlan() async {
        let store = MemoryStore(MacroFixtures.plan())
        let loader = makeLoader(store: store, provider: FakeProvider(failure: PlanAPIError.planUnavailable(reason: "timeout")))

        let done = await loader.regenerate(snapshot: TestFixtures.snapshot)

        XCTAssertFalse(done)
        XCTAssertEqual(loader.plan, MacroFixtures.plan())
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(loader.error, PlanAPIError.planUnavailable(reason: "timeout").errorDescription)
    }

    func testRegenerateIgnoresTheDailyLimitAndClearsAnEarlierError() async {
        let provider = FakeProvider()
        let marker = MemoryMarker()
        marker.marker = "2026-09-30|\(MacroFixtures.goalKey)"
        let loader = makeLoader(provider: provider, marker: marker)

        let done = await loader.regenerate(snapshot: TestFixtures.snapshot)

        XCTAssertTrue(done)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertNil(loader.error)
    }

    func testWithoutATokenItAsksForConfiguration() async {
        let loader = makeLoader(provider: nil)

        let done = await loader.regenerate(snapshot: TestFixtures.snapshot)

        XCTAssertFalse(done)
        XCTAssertTrue(loader.needsConfiguration)
    }

    func testWeeksOverlappingTheNextSevenDaysAreUniqueAndKnown() {
        let loader = makeLoader(store: MemoryStore(MacroFixtures.plan()), provider: nil)
        let dates = WeekCalendar(calendar: TestFixtures.utc).dates(from: "2026-09-30", count: 7)

        XCTAssertEqual(loader.weeks(overlapping: dates).map(\.weekStart), ["2026-09-28", "2026-10-05"])
        XCTAssertEqual(loader.weeks(overlapping: ["2026-10-30"]), [])
        XCTAssertEqual(makeLoader(provider: nil).weeks(overlapping: dates), [])
    }

    func testWeeksUntilTheGoal() {
        XCTAssertEqual(makeLoader(store: MemoryStore(MacroFixtures.plan()), provider: nil).weeksUntilGoal, 40)
        XCTAssertEqual(makeLoader(provider: nil).weeksUntilGoal, 0)
    }
}
