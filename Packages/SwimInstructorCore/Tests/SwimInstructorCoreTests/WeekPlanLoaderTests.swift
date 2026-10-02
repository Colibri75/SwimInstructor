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
        let json: String
        init(failure: Error? = nil, json: String = WeekFixtures.responseJSON) {
            self.failure = failure
            self.json = json
        }

        func fetchWeekPlan(_ request: WeekPlanRequest) async throws -> WeekPlanResponse {
            requests.append(request)
            if let failure { throw failure }
            return try PlanResponse.jsonDecoder().decode(WeekPlanResponse.self, from: Data(json.utf8))
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
        workouts: [SwimWorkout] = [],
        withContext: Bool = true,
        marker: DailyRefreshMarking = MemoryMarker()
    ) -> WeekPlanLoader {
        let loader = WeekPlanLoader(
            store: store,
            planProvider: { provider },
            dailyMarker: marker,
            now: { TestFixtures.now },
            calendar: TestFixtures.utc
        )
        if withContext {
            loader.contextProvider = { WeekPlanLoader.PlanningContext(snapshot: TestFixtures.snapshot, workouts: workouts) }
        }
        return loader
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

    func testPlanningTheNextDaysAsksForSevenDaysFromTodayAndStoresTheResult() async {
        let store = MemoryStore()
        let provider = FakeProvider()
        let loader = makeLoader(store: store, provider: provider)

        let planned = await loader.planNextDays()

        let request = provider.requests.first
        XCTAssertTrue(planned)
        XCTAssertEqual(provider.requests.count, 1)
        // Rollender Plan: keine Kalenderwoche, die sieben Tage ab heute.
        XCTAssertNil(request?.weekStart)
        XCTAssertEqual(request?.fromDate, "2026-09-30")
        XCTAssertEqual(request?.today, "2026-09-30")
        XCTAssertEqual(request?.unavailableDates, [])
        XCTAssertEqual(request?.swumThisWeek, [])
        XCTAssertEqual(request?.recentSwim, [])
        XCTAssertEqual(request?.macroWeeks, [])
        XCTAssertNil(request?.wishes)
        XCTAssertEqual(loader.weeks.count, 1)
        XCTAssertEqual(store.stored.count, 1)
        XCTAssertEqual(loader.selectedWeek?.days.count, 3)
        XCTAssertNil(loader.error)
        XCTAssertFalse(loader.isLoading)
    }

    func testRequestCarriesTheLastSevenDaysAndTheDaysWithoutTime() async {
        let existing = WeekPlanEditor.markUnavailable(WeekFixtures.plan(), date: "2026-10-02")
        let workouts = [
            TestFixtures.workout(daysAgo: 2, meters: 1000),           // Mo 28.09.
            TestFixtures.workout(daysAgo: 1, meters: 500, hour: 8),   // Di
            TestFixtures.workout(daysAgo: 1, meters: 300, hour: 18),  // Di, zweite Einheit
            TestFixtures.workout(daysAgo: 5, meters: 700),            // Fr 25.09., noch die Vorwoche
            TestFixtures.workout(daysAgo: 9, meters: 900),            // 21.09., zu lange her
            TestFixtures.workout(daysAgo: 0, meters: 400, hour: 8)    // heute zählt noch nicht
        ]
        let provider = FakeProvider()
        let loader = makeLoader(store: MemoryStore([existing]), provider: provider, workouts: workouts)

        await loader.planNextDays(wishes: "mehr Technik")

        let request = provider.requests.first
        XCTAssertEqual(request?.recentSwim, [
            SwumDay(date: "2026-09-25", meters: 700),
            SwumDay(date: "2026-09-28", meters: 1000),
            SwumDay(date: "2026-09-29", meters: 800)
        ])
        XCTAssertEqual(request?.swumThisWeek, [])
        XCTAssertEqual(request?.unavailableDates, ["2026-10-02"])
        XCTAssertEqual(request?.wishes, "mehr Technik")
        // Der Tag ohne Zeit bleibt trotz anderem Vorschlag des Servers ein Ruhetag.
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-02")?.isUnavailable, true)
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-02")?.targetDistanceMeters, 0)
    }

    func testTheOwnedEquipmentAndTheMacroWeeksGoIntoTheRequest() async {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider)
        let macro = MacroWeek(weekStart: "2026-09-28", targetMeters: 3500, sessions: 3, deload: false, focus: "Ausdauer", phase: .specific)
        var askedDates: [String] = []
        loader.equipmentProvider = { ["fins"] }
        loader.macroProvider = { dates in
            askedDates = dates
            return [macro]
        }

        await loader.planNextDays()

        XCTAssertEqual(provider.requests.first?.equipment, ["fins"])
        XCTAssertEqual(provider.requests.first?.macroWeeks, [macro])
        XCTAssertEqual(askedDates, ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06"])
    }

    func testReplanningKeepsTheDaysThatAreOver() async {
        let past = WeekFixtures.day("2026-09-28", WeekFixtures.content(meters: 1234))
        let existing = WeekFixtures.plan(days: [past] + WeekFixtures.plan().days)
        let loader = makeLoader(store: MemoryStore([existing]), provider: FakeProvider())

        await loader.planNextDays()

        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-09-28")?.targetDistanceMeters, 1234)
        XCTAssertEqual(loader.selectedWeek?.day(on: "2026-10-02")?.focus, "Technik mit Pull Buoy")
        // Im Fenster, aber vom Server nicht mehr vorgesehen: gilt der neue Plan.
        XCTAssertNil(loader.selectedWeek?.day(on: "2026-10-03"))
    }

    func testTheNextSevenDaysAreSplitIntoCalendarWeeks() async {
        // Sa 03.10. bis Di 06.10.: zwei Tage in dieser Woche, zwei in der nächsten.
        let provider = FakeProvider(json: WeekFixtures.responseAcrossTwoWeeksJSON)
        let store = MemoryStore()
        let loader = makeLoader(store: store, provider: provider)

        await loader.planNextDays()

        XCTAssertEqual(loader.weeks.map(\.weekStart), ["2026-09-28", "2026-10-05"])
        XCTAssertEqual(loader.week(starting: "2026-09-28")?.days.map(\.date), ["2026-10-03", "2026-10-04"])
        XCTAssertEqual(loader.week(starting: "2026-10-05")?.days.map(\.date), ["2026-10-05", "2026-10-06"])
        XCTAssertEqual(loader.week(starting: "2026-10-05")?.rationale, "Zwei Wochen.")
        XCTAssertEqual(store.stored.count, 2)
    }

    func testDaysBeyondTheWindowKeepTheirOlderPlan() async {
        // Eine ältere Planung kannte schon den Donnerstag der nächsten Woche (08.10.), das Fenster endet am 06.10.
        let later = WeekPlan(weekStart: "2026-10-05", generatedAt: TestFixtures.now, rationale: "alt", days: [WeekFixtures.day("2026-10-08", WeekFixtures.content(meters: 1800))])
        let loader = makeLoader(store: MemoryStore([later]), provider: FakeProvider(json: WeekFixtures.responseAcrossTwoWeeksJSON))

        await loader.planNextDays()

        XCTAssertEqual(loader.week(starting: "2026-10-05")?.days.map(\.date), ["2026-10-05", "2026-10-06", "2026-10-08"])
        XCTAssertEqual(loader.week(starting: "2026-10-05")?.day(on: "2026-10-08")?.targetDistanceMeters, 1800)
    }

    func testWithoutHealthDataThereIsAHintAndNoRequest() async {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider, withContext: false)

        let planned = await loader.planNextDays()

        XCTAssertFalse(planned)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(loader.error, "Die Health-Daten sind noch nicht geladen. Öffne zuerst den Tab Heute.")
    }

    func testWithoutATokenItAsksForConfiguration() async {
        let loader = makeLoader(provider: nil)

        let planned = await loader.planNextDays()

        XCTAssertFalse(planned)
        XCTAssertTrue(loader.needsConfiguration)
        XCTAssertTrue(loader.weeks.isEmpty)
    }

    func testAFailureKeepsTheOldPlanAndShowsTheError() async {
        let store = MemoryStore([WeekFixtures.plan()])
        let loader = makeLoader(store: store, provider: FakeProvider(failure: PlanAPIError.planUnavailable(reason: "timeout")))

        let planned = await loader.planNextDays()

        XCTAssertFalse(planned)
        XCTAssertEqual(loader.weeks, [WeekFixtures.plan()])
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(loader.error, PlanAPIError.planUnavailable(reason: "timeout").errorDescription)
        XCTAssertFalse(loader.isLoading)
    }

    func testASuccessfulPlanClearsAnEarlierError() async {
        let loader = makeLoader(provider: FakeProvider(), withContext: false)
        await loader.planNextDays()
        XCTAssertNotNil(loader.error)

        loader.contextProvider = { WeekPlanLoader.PlanningContext(snapshot: TestFixtures.snapshot, workouts: []) }
        await loader.planNextDays()

        XCTAssertNil(loader.error)
    }

    // MARK: - Einmal am Tag

    func testTheDailyRefreshRunsOncePerDay() async {
        let provider = FakeProvider()
        let marker = MemoryMarker()
        let loader = makeLoader(provider: provider, marker: marker)

        await loader.refreshDaily()
        await loader.refreshDaily()
        await loader.refreshDaily()

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(marker.marker, "2026-09-30|")
    }

    func testTheDailyRefreshIsRetriedAfterAFailure() async {
        let marker = MemoryMarker()
        let failing = makeLoader(provider: FakeProvider(failure: PlanAPIError.network("aus")), marker: marker)

        await failing.refreshDaily()
        XCTAssertNil(marker.marker)

        let provider = FakeProvider()
        let working = makeLoader(provider: provider, marker: marker)
        await working.refreshDaily()

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(marker.marker, "2026-09-30|")
    }

    func testTheDailyRefreshRunsAgainWhenTheStampChangesAndOnANewDay() async {
        let provider = FakeProvider()
        let marker = MemoryMarker()
        marker.marker = "2026-09-29|"
        let loader = makeLoader(provider: provider, marker: marker)

        await loader.refreshDaily(stamp: "ziel-a")
        await loader.refreshDaily(stamp: "ziel-a")
        await loader.refreshDaily(stamp: "ziel-b")

        XCTAssertEqual(provider.requests.count, 2)
        XCTAssertEqual(marker.marker, "2026-09-30|ziel-b")
    }

    func testTheDailyRefreshGivesTheDailyWishToThePlan() async {
        let provider = FakeProvider()
        let loader = makeLoader(provider: provider)

        await loader.refreshDaily(wishes: "Schulter schonen")

        XCTAssertEqual(provider.requests.first?.wishes, "Schulter schonen")
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

        await loader.planNextDays()

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
}
