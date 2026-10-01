import XCTest
@testable import SwimInstructorCore

@MainActor
final class WeekPlanLoaderTests: XCTestCase {
    private final class MemoryStore: WeekPlanStoring {
        var stored: [WeekPlan]
        private(set) var saves = 0
        init(_ stored: [WeekPlan] = []) { self.stored = stored }
        func load() -> [WeekPlan] { stored }
        func save(_ plans: [WeekPlan]) throws {
            stored = plans
            saves += 1
        }
    }

    private final class FakeProvider: WeekPlanProviding, @unchecked Sendable {
        private(set) var requests: [WeekPlanRequest] = []
        let failure: Error?
        init(failure: Error? = nil) { self.failure = failure }

        func fetchWeekPlan(_ request: WeekPlanRequest) async throws -> WeekPlanResponse {
            requests.append(request)
            if let failure { throw failure }
            return try PlanResponse.jsonDecoder().decode(WeekPlanResponse.self, from: Data(WeekFixtures.responseJSON.utf8))
        }
    }

    private func makeLoader(
        store: MemoryStore = MemoryStore(),
        provider: FakeProvider?,
        workouts: [SwimWorkout] = [],
        withContext: Bool = true
    ) -> WeekPlanLoader {
        let loader = WeekPlanLoader(
            store: store,
            planProvider: { provider },
            now: { TestFixtures.now },
            calendar: TestFixtures.utc
        )
        if withContext {
            loader.contextProvider = { WeekPlanLoader.PlanningContext(snapshot: TestFixtures.snapshot, workouts: workouts) }
        }
        return loader
    }

    func testTheWeekRequestCarriesTheOwnedEquipment() async {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider)
        loader.equipmentProvider = { ["fins", "snorkel"] }

        await loader.plan(weekStarting: "2026-09-28")

        XCTAssertEqual(provider.requests.first?.equipment, ["fins", "snorkel"])
    }

    // MARK: - Lesen

    func testStartsOnTheCurrentWeekAndKnowsToday() {
        let loader = makeLoader(provider: nil)

        XCTAssertEqual(loader.currentWeekStart, "2026-09-28")
        XCTAssertEqual(loader.selectedWeekStart, "2026-09-28")
        XCTAssertEqual(loader.todayKey, "2026-09-30")
        XCTAssertNil(loader.selectedWeek)
        XCTAssertNil(loader.todayEntry)
        XCTAssertNil(loader.todayTarget)
    }

    func testLoadsStoredWeeksAndFindsTheEntryForToday() {
        let loader = makeLoader(store: MemoryStore([WeekFixtures.plan()]), provider: nil)

        XCTAssertEqual(loader.weeks.count, 1)
        XCTAssertEqual(loader.selectedWeek?.weekStart, "2026-09-28")
        XCTAssertEqual(loader.todayEntry?.targetDistanceMeters, 1500)
        XCTAssertEqual(loader.todayTarget, DayPlanTarget(sessionType: .endurance, intensity: .moderate, targetDistanceMeters: 1500, focus: "Ausdauer"))
    }

    func testEditableFromTodayOn() {
        let loader = makeLoader(provider: nil)

        XCTAssertFalse(loader.isEditable("2026-09-29"))
        XCTAssertTrue(loader.isEditable("2026-09-30"))
        XCTAssertTrue(loader.isEditable("2026-10-04"))
    }

    // MARK: - Planen

    func testPlanningTheCurrentWeekStartsTodayAndStoresTheResult() async {
        let store = MemoryStore()
        let provider = FakeProvider()
        let loader = makeLoader(store: store, provider: provider)

        await loader.plan(weekStarting: "2026-09-28")

        let request = provider.requests.first
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(request?.weekStart, "2026-09-28")
        XCTAssertEqual(request?.fromDate, "2026-09-30")
        XCTAssertEqual(request?.today, "2026-09-30")
        XCTAssertEqual(request?.unavailableDates, [])
        XCTAssertEqual(request?.swumThisWeek, [])
        XCTAssertNil(request?.wishes)
        XCTAssertEqual(loader.weeks.count, 1)
        XCTAssertEqual(store.stored.count, 1)
        XCTAssertEqual(loader.selectedWeek?.days.count, 3)
        XCTAssertNil(loader.error)
        XCTAssertFalse(loader.isLoading)
    }

    func testRequestCarriesWhatWasSwumBeforeTodayAndTheDaysWithoutTime() async {
        let existing = WeekPlanEditor.markUnavailable(WeekFixtures.plan(), date: "2026-10-02")
        let workouts = [
            TestFixtures.workout(daysAgo: 2, meters: 1000),           // Mo
            TestFixtures.workout(daysAgo: 1, meters: 500, hour: 8),   // Di
            TestFixtures.workout(daysAgo: 1, meters: 300, hour: 18),  // Di, zweite Einheit
            TestFixtures.workout(daysAgo: 5, meters: 700),            // Vorwoche
            TestFixtures.workout(daysAgo: 0, meters: 400, hour: 8)    // heute zählt noch nicht
        ]
        let provider = FakeProvider()
        let loader = makeLoader(store: MemoryStore([existing]), provider: provider, workouts: workouts)

        await loader.plan(weekStarting: "2026-09-28", wishes: "mehr Technik")

        let request = provider.requests.first
        XCTAssertEqual(request?.swumThisWeek, [SwumDay(date: "2026-09-28", meters: 1000), SwumDay(date: "2026-09-29", meters: 800)])
        XCTAssertEqual(request?.unavailableDates, ["2026-10-02"])
        XCTAssertEqual(request?.wishes, "mehr Technik")
        // Der Tag ohne Zeit bleibt trotz anderem Vorschlag des Servers ein Ruhetag.
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-02")?.isUnavailable, true)
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-02")?.targetDistanceMeters, 0)
    }

    func testReplanningKeepsTheDaysThatAreOver() async {
        let past = WeekFixtures.day("2026-09-28", WeekFixtures.content(meters: 1234))
        let existing = WeekFixtures.plan(days: [past] + WeekFixtures.plan().days)
        let loader = makeLoader(store: MemoryStore([existing]), provider: FakeProvider())

        await loader.plan(weekStarting: "2026-09-28")

        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-09-28")?.targetDistanceMeters, 1234)
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-02")?.focus, "Technik mit Pull Buoy")
        XCTAssertNil(loader.selectedWeek?.day(on: "2026-10-03"))
    }

    func testPlanningNextWeekStartsOnMonday() async {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider, workouts: [TestFixtures.workout(daysAgo: 2, meters: 1000)])

        await loader.plan(weekStarting: "2026-10-05")

        XCTAssertEqual(provider.requests.first?.fromDate, "2026-10-05")
        XCTAssertEqual(provider.requests.first?.today, "2026-09-30")
        XCTAssertEqual(provider.requests.first?.swumThisWeek, [])
    }

    func testAPastWeekCannotBePlanned() async {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider)

        await loader.plan(weekStarting: "2026-09-21")

        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertNotNil(loader.error)
        XCTAssertFalse(loader.canPlan(weekStarting: "2026-09-21"))
        XCTAssertTrue(loader.canPlan(weekStarting: "2026-09-28"))
    }

    func testWithoutHealthDataThereIsAHintAndNoRequest() async {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider, withContext: false)

        await loader.plan(weekStarting: "2026-09-28")

        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(loader.error, "Die Health-Daten sind noch nicht geladen. Öffne zuerst den Tab Heute.")
    }

    func testWithoutATokenItAsksForConfiguration() async {
        let loader = makeLoader(provider: nil)

        await loader.plan(weekStarting: "2026-09-28")

        XCTAssertTrue(loader.needsConfiguration)
        XCTAssertTrue(loader.weeks.isEmpty)
    }

    func testAFailureKeepsTheOldPlanAndShowsTheError() async {
        let store = MemoryStore([WeekFixtures.plan()])
        let loader = makeLoader(store: store, provider: FakeProvider(failure: PlanAPIError.planUnavailable(reason: "timeout")))

        await loader.plan(weekStarting: "2026-09-28")

        XCTAssertEqual(loader.weeks, [WeekFixtures.plan()])
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(loader.error, PlanAPIError.planUnavailable(reason: "timeout").errorDescription)
        XCTAssertFalse(loader.isLoading)
    }

    func testASuccessfulPlanClearsAnEarlierError() async {
        let loader = makeLoader(provider: FakeProvider(), withContext: false)
        await loader.plan(weekStarting: "2026-09-28")
        XCTAssertNotNil(loader.error)

        loader.contextProvider = { WeekPlanLoader.PlanningContext(snapshot: TestFixtures.snapshot, workouts: []) }
        await loader.plan(weekStarting: "2026-09-28")

        XCTAssertNil(loader.error)
    }

    // MARK: - Ändern

    func testEditsAreAppliedToTheShownWeekAndSaved() {
        let store = MemoryStore([WeekFixtures.plan()])
        let loader = makeLoader(store: store, provider: nil)

        loader.markUnavailable("2026-10-02")
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-02")?.isUnavailable, true)
        XCTAssertEqual(store.saves, 1)

        loader.clearUnavailable("2026-10-02")
        loader.setDistance("2026-10-03", meters: 1500)
        loader.setRest("2026-09-30")
        loader.swapDays("2026-10-01", "2026-10-03")
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-02")?.isUnavailable, false)
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-01")?.targetDistanceMeters, 1500)
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-03")?.isRestDay, true)
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-09-30")?.isRestDay, true)
        XCTAssertEqual(store.stored.first, loader.selectedWeek)
    }

    func testMovingAMissedSessionToARestDay() {
        let past = WeekFixtures.day("2026-09-29", WeekFixtures.content(meters: 1100))
        let loader = makeLoader(store: MemoryStore([WeekFixtures.plan(days: [past] + WeekFixtures.plan().days)]), provider: nil)

        loader.moveToRestDay(from: "2026-09-29", to: "2026-10-01")

        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-01")?.targetDistanceMeters, 1100)
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-09-29")?.isRestDay, true)
    }

    func testAnEditWithoutAPlanOrWithoutEffectDoesNotSave() {
        let store = MemoryStore()
        let empty = makeLoader(store: store, provider: nil)
        empty.markUnavailable("2026-10-02")
        XCTAssertEqual(store.saves, 0)

        let filled = MemoryStore([WeekFixtures.plan()])
        let loader = makeLoader(store: filled, provider: nil)
        loader.clearUnavailable("2026-10-02")
        XCTAssertEqual(filled.saves, 0)
    }

    func testOnlyTheLastEightWeeksAreKept() async {
        let old = (0..<8).map { offset -> WeekPlan in
            let start = WeekCalendar(calendar: TestFixtures.utc).addingDays(-7 * (offset + 1), to: "2026-09-28") ?? ""
            return WeekPlan(weekStart: start, generatedAt: TestFixtures.now, rationale: "alt", days: [])
        }
        let store = MemoryStore(old)
        let loader = makeLoader(store: store, provider: FakeProvider())

        await loader.plan(weekStarting: "2026-09-28")

        XCTAssertEqual(loader.weeks.count, WeekPlanLoader.retainedWeeks)
        XCTAssertEqual(loader.weeks.last?.weekStart, "2026-09-28")
        XCTAssertFalse(loader.weeks.contains { $0.weekStart == "2026-08-03" })
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
    }

    func testFirstPlannedDate() {
        let loader = makeLoader(provider: nil)

        XCTAssertEqual(loader.firstPlannedDate(forWeekStarting: "2026-09-28"), "2026-09-30")
        XCTAssertEqual(loader.firstPlannedDate(forWeekStarting: "2026-10-05"), "2026-10-05")
    }
}
