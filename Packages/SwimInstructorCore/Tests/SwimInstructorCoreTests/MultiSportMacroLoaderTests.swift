import XCTest
@testable import SwimInstructorCore

/// Ziele und Antworten für die Tests des Gesamtplans v2. "Heute" ist Mittwoch, der 30.09.2026 (TestFixtures.now).
private enum MacroLoaderV2Data {
    /// Sonntag, 08.11.2026, wie `goal_day` in den Vertragsbeispielen.
    static let goalDate: Date = TestFixtures.utc.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12)) ?? TestFixtures.now

    /// Sprint-Triathlon: 750 m Schwimmen in 20 Minuten, 20 km Rad, 5 km Laufen.
    static func sprint(weeklyHours: Double = 6, trainingDays: Int = 5, swimSeconds: TimeInterval = 1_200) -> TrainingGoal {
        TrainingGoal(
            template: nil,
            disciplines: [
                TrainingGoal.Discipline(sport: .swim, distanceMeters: 750, targetDurationSeconds: swimSeconds),
                TrainingGoal.Discipline(sport: .bike, distanceMeters: 20_000),
                TrainingGoal.Discipline(sport: .run, distanceMeters: 5_000)
            ],
            targetDate: goalDate,
            trainingDaysPerWeek: trainingDays,
            weeklyHours: weeklyHours,
            emphasis: [
                TrainingGoal.Emphasis(sport: .swim, percent: 30),
                TrainingGoal.Emphasis(sport: .bike, percent: 40),
                TrainingGoal.Emphasis(sport: .run, percent: 30)
            ]
        )
    }

    static func key(_ goal: TrainingGoal) -> String {
        goal.planKey(calendar: TestFixtures.utc)
    }

    static var sprintKey: String { key(sprint()) }

    static func response(_ file: String) throws -> MacroPlanV2Response {
        let data = try RepoPaths.contractData("wire/\(file)")
        return try PlanResponse.jsonDecoder().decode(MacroPlanV2Response.self, from: data)
    }

    /// Sechs Wochen ab dem 28.09. bis zum Ziel am 08.11.
    static func macroResponse() throws -> MacroPlanV2Response {
        try response("plan-v2-macro-response.json")
    }

    /// Die Überarbeitung "mehr Laufen, weniger Schwimmen" mit Änderungen und Feedback.
    static func revisedResponse() throws -> MacroPlanV2Response {
        try response("plan-v2-revise-response.json")
    }

    /// Dieselbe Überarbeitung ohne `changes` und `feedback`.
    static func revisedResponseWithoutDetails() throws -> MacroPlanV2Response {
        let data = try RepoPaths.contractData("wire/plan-v2-revise-response.json")
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestError(message: "kein JSON-Objekt")
        }
        object.removeValue(forKey: "changes")
        object.removeValue(forKey: "feedback")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        return try PlanResponse.jsonDecoder().decode(MacroPlanV2Response.self, from: stripped)
    }

    /// Der Gesamtplan aus dem Vertragsbeispiel, wie die App ihn speichert.
    /// Mit früheren Runden auch mit einer Fortschreibung danach, damit wieder Feedback geht (P4).
    static func storedPlan(goalKey: String = MacroLoaderV2Data.sprintKey, rounds: [MacroFeedbackRound] = []) throws -> MacroPlanV2 {
        var plan = try macroResponse().macroPlan(goalKey: goalKey, feedbackRounds: rounds)
        if !rounds.isEmpty { plan.reviews = [laterReview] }
        return plan
    }

    static let laterReview = MacroReview(
        reviewedAt: TestFixtures.date(daysAgo: 2, hour: 9), weekStart: "2026-09-28", reason: .scheduled, summary: "Alles nach Plan.", changes: []
    )

    static let earlierRound = MacroFeedbackRound(
        feedback: "Weniger Rad unter der Woche", changes: ["Rad dienstags 10 Minuten kürzer"], revisedAt: TestFixtures.date(daysAgo: 3, hour: 9)
    )
}

@MainActor
final class MultiSportMacroLoaderTests: XCTestCase {
    private final class MemoryStore: MacroPlanV2Storing {
        var stored: MacroPlanV2?
        private(set) var saves = 0
        init(_ stored: MacroPlanV2? = nil) { self.stored = stored }
        func load() -> MacroPlanV2? { stored }
        func save(_ plan: MacroPlanV2) throws {
            stored = plan
            saves += 1
        }
    }

    private final class FakeProvider: MacroPlanV2Providing, @unchecked Sendable {
        private(set) var macroRequests: [MacroPlanV2Request] = []
        private(set) var revisionRequests: [MacroRevisionRequest] = []
        private(set) var reviewRequests: [MacroReviewRequest] = []
        let macro: MacroPlanV2Response
        let revised: MacroPlanV2Response
        let failure: Error?

        init(macro: MacroPlanV2Response, revised: MacroPlanV2Response, failure: Error?) {
            self.macro = macro
            self.revised = revised
            self.failure = failure
        }

        func fetchMacroPlanV2(_ request: MacroPlanV2Request) async throws -> MacroPlanV2Response {
            macroRequests.append(request)
            if let failure { throw failure }
            return macro
        }

        func reviseMacroPlan(_ request: MacroRevisionRequest) async throws -> MacroPlanV2Response {
            revisionRequests.append(request)
            if let failure { throw failure }
            return revised
        }

        func reviewMacroPlan(_ request: MacroReviewRequest) async throws -> MacroPlanV2Response {
            reviewRequests.append(request)
            if let failure { throw failure }
            return try MacroLoaderV2Data.response("plan-v2-review-response.json")
        }
    }

    private final class MemoryMarker: DailyRefreshMarking {
        var marker: String?
        func lastDay() -> String? { marker }
        func setLastDay(_ marker: String) { self.marker = marker }
    }

    private func makeProvider(failure: Error? = nil, revised: MacroPlanV2Response? = nil) throws -> FakeProvider {
        let macro = try MacroLoaderV2Data.macroResponse()
        let revisedResponse: MacroPlanV2Response
        if let revised {
            revisedResponse = revised
        } else {
            revisedResponse = try MacroLoaderV2Data.revisedResponse()
        }
        return FakeProvider(macro: macro, revised: revisedResponse, failure: failure)
    }

    private func makeLoader(
        store: MemoryStore = MemoryStore(),
        provider: FakeProvider?,
        goal: @escaping @MainActor () -> TrainingGoal = { MacroLoaderV2Data.sprint() },
        goalVersion: (@MainActor () -> Int)? = nil,
        marker: MemoryMarker = MemoryMarker(),
        reviewMarker: MemoryMarker = MemoryMarker(),
        now: Date = TestFixtures.now
    ) -> MultiSportMacroLoader {
        MultiSportMacroLoader(
            store: store,
            planProvider: { provider },
            goal: goal,
            goalVersion: goalVersion,
            attemptMarker: marker,
            reviewMarker: reviewMarker,
            now: { now },
            calendar: TestFixtures.utc
        )
    }

    // MARK: - Lesen

    func testLoadsTheStoredPlanAndReadsItsWeeks() throws {
        let plan = try MacroLoaderV2Data.storedPlan()
        let loader = makeLoader(store: MemoryStore(plan), provider: nil)

        XCTAssertEqual(loader.plan, plan)
        XCTAssertEqual(loader.todayKey, "2026-09-30")
        XCTAssertEqual(loader.currentWeekStart, "2026-09-28")
        XCTAssertEqual(loader.currentGoalKey, MacroLoaderV2Data.sprintKey)
        XCTAssertEqual(loader.currentWeek?.weekStart, "2026-09-28")
        XCTAssertEqual(loader.currentWeek?.tests.first?.testID, "threshold_30min")
        XCTAssertEqual(loader.upcomingWeeks.count, 6)
        XCTAssertTrue(loader.isCurrent)
    }

    func testThePlanIsCurrentOnlyForTheSameGoalAndWithTheRunningWeek() throws {
        let plan = try MacroLoaderV2Data.storedPlan()
        var goal = MacroLoaderV2Data.sprint()
        let loader = makeLoader(store: MemoryStore(plan), provider: nil, goal: { goal })
        XCTAssertTrue(loader.isCurrent)

        // Mehr Stunden pro Woche kommen aus dem Wochenraster: Der Plan bleibt.
        goal = MacroLoaderV2Data.sprint(weeklyHours: 8, trainingDays: 4)
        XCTAssertTrue(loader.isCurrent)

        // Eine andere Zielzeit: ein anderes Ziel, der Plan passt nicht mehr.
        goal = MacroLoaderV2Data.sprint(swimSeconds: 1_100)
        XCTAssertNotEqual(loader.currentGoalKey, plan.goalKey)
        XCTAssertFalse(loader.isCurrent)

        // Ein anderer Zieltag ebenso.
        goal = MacroLoaderV2Data.sprint()
        XCTAssertTrue(loader.isCurrent)
        goal.targetDate = TestFixtures.utc.date(byAdding: .day, value: 7, to: MacroLoaderV2Data.goalDate) ?? TestFixtures.now
        XCTAssertFalse(loader.isCurrent)

        // Ohne Plan, mit fremdem Schlüssel oder abgelaufen (die laufende Woche fehlt).
        XCTAssertFalse(makeLoader(provider: nil).isCurrent)
        let foreign = try MacroLoaderV2Data.storedPlan(goalKey: "anderes-ziel")
        XCTAssertFalse(makeLoader(store: MemoryStore(foreign), provider: nil).isCurrent)
        let expired = MacroPlanV2(
            goalKey: plan.goalKey, goalDay: plan.goalDay, generatedAt: plan.generatedAt, rationale: plan.rationale,
            weeks: Array(plan.weeks.dropFirst())
        )
        XCTAssertFalse(makeLoader(store: MemoryStore(expired), provider: nil).isCurrent)
    }

    func testWeeksOverlappingTheNextSevenDaysAreUniqueAndKnown() throws {
        let plan = try MacroLoaderV2Data.storedPlan()
        let loader = makeLoader(store: MemoryStore(plan), provider: nil)
        let dates = WeekCalendar(calendar: TestFixtures.utc).dates(from: "2026-09-30", count: 7)

        XCTAssertEqual(loader.weeks(overlapping: dates).map(\.weekStart), ["2026-09-28", "2026-10-05"])
        XCTAssertEqual(loader.weeks(overlapping: ["2026-10-06", "2026-10-05", "2026-10-01"]).map(\.weekStart), ["2026-10-05", "2026-09-28"])
        XCTAssertEqual(loader.weeks(overlapping: ["2026-12-30", "kaputt"]), [])
        XCTAssertEqual(makeLoader(provider: nil).weeks(overlapping: dates), [])
    }

    func testWeeksUntilTheGoal() throws {
        // 39 Tage bis zum 08.11.: sechs angebrochene Wochen.
        let plan = try MacroLoaderV2Data.storedPlan()
        XCTAssertEqual(makeLoader(store: MemoryStore(plan), provider: nil).weeksUntilGoal, 6)
        XCTAssertEqual(makeLoader(provider: nil).weeksUntilGoal, 0)

        let past = MacroPlanV2(
            goalKey: MacroLoaderV2Data.sprintKey, goalDay: "2026-09-20", generatedAt: TestFixtures.now, rationale: "vorbei", weeks: []
        )
        XCTAssertEqual(makeLoader(store: MemoryStore(past), provider: nil).weeksUntilGoal, 0)
    }

    // MARK: - Erneuern

    func testEnsureCurrentFetchesStoresAndMarksAMissingPlan() async throws {
        let store = MemoryStore()
        let provider = try makeProvider()
        let marker = MemoryMarker()
        let loader = makeLoader(store: store, provider: provider, marker: marker)
        let settings = TestSettings(offer: false, intervalWeeks: 6)
        loader.testSettingsProvider = { settings }

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.macroRequests, [MacroPlanV2Request(snapshot: TestFixtures.snapshot, today: "2026-09-30", testSettings: settings)])
        XCTAssertTrue(provider.revisionRequests.isEmpty)
        let plan = try XCTUnwrap(loader.plan)
        XCTAssertEqual(plan.goalKey, MacroLoaderV2Data.sprintKey)
        XCTAssertEqual(plan.goalDay, "2026-11-08")
        XCTAssertEqual(plan.weeks.count, 6)
        XCTAssertEqual(plan.sports, [SportID.swim, SportID.bike, SportID.run])
        XCTAssertEqual(plan.feedbackRounds, [])
        XCTAssertEqual(store.stored, plan)
        XCTAssertEqual(store.saves, 1)
        XCTAssertEqual(marker.marker, "2026-09-30|\(MacroLoaderV2Data.sprintKey)")
        XCTAssertTrue(loader.isCurrent)
        XCTAssertNil(loader.error)
        XCTAssertFalse(loader.isLoading)
    }

    func testEnsureCurrentDoesNothingWhileThePlanIsCurrent() async throws {
        let provider = try makeProvider()
        let plan = try MacroLoaderV2Data.storedPlan()
        let loader = makeLoader(store: MemoryStore(plan), provider: provider)

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertTrue(provider.macroRequests.isEmpty)
    }

    func testEnsureCurrentTriesOncePerDayAndGoalEvenAfterAFailure() async throws {
        var goal = MacroLoaderV2Data.sprint()
        let provider = try makeProvider(failure: PlanAPIError.network("aus"))
        let marker = MemoryMarker()
        let loader = makeLoader(provider: provider, goal: { goal }, marker: marker)

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)
        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)
        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.macroRequests.count, 1)
        XCTAssertNotNil(loader.error)
        XCTAssertNil(loader.plan)

        // Ein neues Ziel am selben Tag bekommt einen eigenen Versuch.
        goal = MacroLoaderV2Data.sprint(swimSeconds: 1_150)
        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.macroRequests.count, 2)
        XCTAssertEqual(marker.marker, "2026-09-30|\(MacroLoaderV2Data.key(goal))")
    }

    func testEnsureCurrentTriesAgainOnANewDay() async throws {
        let provider = try makeProvider()
        let marker = MemoryMarker()
        marker.marker = "2026-09-29|\(MacroLoaderV2Data.sprintKey)"
        let loader = makeLoader(provider: provider, marker: marker)

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.macroRequests.count, 1)
        XCTAssertNotNil(loader.plan)
    }

    func testAChangedGoalIsReplannedOnTheSameDay() async throws {
        var goal = MacroLoaderV2Data.sprint()
        let provider = try makeProvider()
        let plan = try MacroLoaderV2Data.storedPlan()
        let loader = makeLoader(store: MemoryStore(plan), provider: provider, goal: { goal })

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)
        XCTAssertTrue(provider.macroRequests.isEmpty)

        goal = MacroLoaderV2Data.sprint(swimSeconds: 1_100)
        XCTAssertFalse(loader.isCurrent)
        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.macroRequests.count, 1)
        XCTAssertEqual(loader.plan?.goalKey, MacroLoaderV2Data.key(goal))
        XCTAssertTrue(loader.isCurrent)
    }

    func testRegenerateStartsAgainWithoutFeedbackRounds() async throws {
        let plan = try MacroLoaderV2Data.storedPlan(goalKey: "altes-ziel", rounds: [MacroLoaderV2Data.earlierRound])
        let store = MemoryStore(plan)
        let provider = try makeProvider()
        let marker = MemoryMarker()
        // Der Knopf in der App fragt auch dann, wenn heute schon ein Versuch war.
        marker.marker = "2026-09-30|\(MacroLoaderV2Data.sprintKey)"
        let loader = makeLoader(store: store, provider: provider, marker: marker)

        let done = await loader.regenerate(snapshot: TestFixtures.snapshot)

        XCTAssertTrue(done)
        XCTAssertEqual(provider.macroRequests.count, 1)
        XCTAssertEqual(loader.plan?.feedbackRounds, [])
        XCTAssertEqual(loader.plan?.goalKey, MacroLoaderV2Data.sprintKey)
        XCTAssertEqual(store.saves, 1)
        XCTAssertNil(loader.error)
    }

    func testAFailedRegenerationKeepsTheOldPlan() async throws {
        let plan = try MacroLoaderV2Data.storedPlan(rounds: [MacroLoaderV2Data.earlierRound])
        let store = MemoryStore(plan)
        let provider = try makeProvider(failure: PlanAPIError.planUnavailable(reason: "timeout"))
        let loader = makeLoader(store: store, provider: provider)

        let done = await loader.regenerate(snapshot: TestFixtures.snapshot)

        XCTAssertFalse(done)
        XCTAssertEqual(loader.plan, plan)
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(loader.error, PlanAPIError.planUnavailable(reason: "timeout").errorDescription)
        XCTAssertFalse(loader.isLoading)
    }

    func testWithoutATokenItAsksForConfiguration() async throws {
        let plan = try MacroLoaderV2Data.storedPlan()
        let loader = makeLoader(store: MemoryStore(plan), provider: nil)

        let regenerated = await loader.regenerate(snapshot: TestFixtures.snapshot)
        XCTAssertFalse(regenerated)
        XCTAssertTrue(loader.needsConfiguration)

        let revised = await loader.revise(feedback: "Mehr Laufen", snapshot: TestFixtures.snapshot)
        XCTAssertFalse(revised)
        XCTAssertTrue(loader.needsConfiguration)
        XCTAssertEqual(loader.plan, plan)
    }

    // MARK: - Feedback

    // MARK: - Zielversion (P3)

    func testWithAGoalVersionFineTuningKeepsThePlanAndANewVersionReplansIt() async throws {
        var goal = MacroLoaderV2Data.sprint()
        var version = 3
        let provider = try makeProvider()
        let plan = try MacroLoaderV2Data.storedPlan(goalKey: "goal-v3")
        let loader = makeLoader(store: MemoryStore(plan), provider: provider, goal: { goal }, goalVersion: { version })
        XCTAssertEqual(loader.currentGoalKey, "goal-v3")
        XCTAssertTrue(loader.isCurrent)

        // Feinjustierung: andere Zielzeit, gleiche Version.
        goal = MacroLoaderV2Data.sprint(swimSeconds: 1_100)
        XCTAssertTrue(loader.isCurrent)
        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)
        XCTAssertTrue(provider.macroRequests.isEmpty)

        version = 4
        XCTAssertFalse(loader.isCurrent)
        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)
        XCTAssertEqual(provider.macroRequests.count, 1)
        XCTAssertEqual(loader.plan?.goalKey, "goal-v4")
    }

    func testAPlanFromBeforeTheGoalVersionMovesOverWhenItMatches() async throws {
        let store = MemoryStore(try MacroLoaderV2Data.storedPlan())
        let provider = try makeProvider()
        var goal = MacroLoaderV2Data.sprint()
        let loader = makeLoader(store: store, provider: provider, goal: { goal }, goalVersion: { 1 })
        XCTAssertTrue(loader.isCurrent)

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertTrue(provider.macroRequests.isEmpty)
        XCTAssertEqual(store.stored?.goalKey, "goal-v1")
        // Danach ändert eine Feinjustierung nichts mehr.
        goal = MacroLoaderV2Data.sprint(swimSeconds: 1_100)
        XCTAssertTrue(loader.isCurrent)
    }

    func testANewPlanKeepsTheRunningWeekOfTheOldOne() async throws {
        let old = try MacroLoaderV2Data.storedPlan(goalKey: "goal-v1")
        let original = try XCTUnwrap(old.week(starting: "2026-09-28"))
        let running = MacroWeekV2(
            weekStart: original.weekStart, phase: original.phase, deload: original.deload, focus: "Alte laufende Woche",
            totalMinutes: original.totalMinutes, load: original.load, sports: original.sports, tests: original.tests
        )
        var withRunning = old
        withRunning.weeks = [running] + old.weeks.dropFirst()
        let provider = try makeProvider()
        let loader = makeLoader(store: MemoryStore(withRunning), provider: provider, goalVersion: { 2 })

        await loader.ensureCurrent(snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.macroRequests.count, 1)
        XCTAssertEqual(loader.plan?.goalKey, "goal-v2")
        XCTAssertEqual(loader.plan?.week(starting: "2026-09-28")?.focus, "Alte laufende Woche")
        XCTAssertEqual(loader.plan?.weeks.count, 6)
        XCTAssertEqual(loader.plan?.week(starting: "2026-10-05"), try MacroLoaderV2Data.macroResponse().plan.weeks.first { $0.weekStart == "2026-10-05" })
    }

    func testRevisingSendsThePlanWithItsEarlierRoundsAndAppendsTheNewRound() async throws {
        // Gespeichert unter einem älteren Schlüssel: Die Überarbeitung behält den Schlüssel des Plans.
        let current = try MacroLoaderV2Data.storedPlan(goalKey: "ziel-beim-planen", rounds: [MacroLoaderV2Data.earlierRound])
        let store = MemoryStore(current)
        let provider = try makeProvider()
        let loader = makeLoader(store: store, provider: provider)
        let settings = TestSettings(offer: true, intervalWeeks: 6, preferred: [TestSettings.Preference(sport: .swim, testID: "css_400_200")])
        loader.testSettingsProvider = { settings }
        let response = try MacroLoaderV2Data.revisedResponse()

        let revised = await loader.revise(feedback: "  mehr laufen, weniger schwimmen \n", snapshot: TestFixtures.snapshot)

        XCTAssertTrue(revised)
        XCTAssertTrue(provider.macroRequests.isEmpty)
        XCTAssertEqual(provider.revisionRequests.count, 1)
        let request = try XCTUnwrap(provider.revisionRequests.first)
        XCTAssertEqual(request.plan, current)
        XCTAssertEqual(request.plan.feedbackRounds, [MacroLoaderV2Data.earlierRound])
        XCTAssertEqual(request.feedback, "mehr laufen, weniger schwimmen")
        XCTAssertEqual(request.today, "2026-09-30")
        XCTAssertEqual(request.snapshot, TestFixtures.snapshot)
        XCTAssertEqual(request.testSettings, settings)

        let plan = try XCTUnwrap(loader.plan)
        let changes = try XCTUnwrap(response.changes)
        let serverFeedback = try XCTUnwrap(response.feedback)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.first, "Laufen in den ersten zwei Wochen 5 Minuten mehr")
        // Die neue Runde hängt hinten an, mit dem Feedback, wie der Server es gelesen hat, und seinen Änderungen.
        XCTAssertEqual(plan.feedbackRounds, [
            MacroLoaderV2Data.earlierRound,
            MacroFeedbackRound(feedback: serverFeedback, changes: changes, adjustments: response.adjustments, revisedAt: TestFixtures.now)
        ])
        XCTAssertEqual(plan.goalKey, "ziel-beim-planen")
        XCTAssertEqual(plan.weeks, response.plan.weeks)
        XCTAssertEqual(plan.rationale, response.plan.rationale)
        XCTAssertEqual(plan.adjustments.count, 2)
        XCTAssertEqual(plan.weeks.first?.volume(of: .swim)?.amount, 3_200)
        XCTAssertEqual(store.stored, plan)
        XCTAssertEqual(store.saves, 1)
        XCTAssertNil(loader.error)
        XCTAssertFalse(loader.isRevising)
    }

    func testWithoutChangesFromTheServerTheRoundKeepsTheAthletesWords() async throws {
        let stripped = try MacroLoaderV2Data.revisedResponseWithoutDetails()
        let provider = try makeProvider(revised: stripped)
        let plan = try MacroLoaderV2Data.storedPlan()
        let loader = makeLoader(store: MemoryStore(plan), provider: provider)

        let revised = await loader.revise(feedback: " weniger Schwimmen ", snapshot: TestFixtures.snapshot)

        XCTAssertTrue(revised)
        let round = try XCTUnwrap(loader.plan?.feedbackRounds.last)
        XCTAssertEqual(loader.plan?.feedbackRounds.count, 1)
        XCTAssertEqual(round.feedback, "weniger Schwimmen")
        XCTAssertEqual(round.changes, [])
    }

    func testEmptyFeedbackSetsAnErrorWithoutARequest() async throws {
        let plan = try MacroLoaderV2Data.storedPlan()
        let store = MemoryStore(plan)
        let provider = try makeProvider()
        let loader = makeLoader(store: store, provider: provider)

        let revised = await loader.revise(feedback: "  \n ", snapshot: TestFixtures.snapshot)

        XCTAssertFalse(revised)
        XCTAssertEqual(loader.error, "Schreib zuerst, was sich am Plan ändern soll.")
        XCTAssertTrue(provider.revisionRequests.isEmpty)
        XCTAssertEqual(loader.plan, plan)
        XCTAssertEqual(store.saves, 0)
    }

    func testRevisingWithoutAPlanSetsAnError() async throws {
        let provider = try makeProvider()
        let loader = makeLoader(provider: provider)

        let revised = await loader.revise(feedback: "Mehr Laufen", snapshot: TestFixtures.snapshot)

        XCTAssertFalse(revised)
        XCTAssertEqual(loader.error, "Es gibt noch keinen Gesamtplan.")
        XCTAssertTrue(provider.revisionRequests.isEmpty)
    }

    func testAFailedRevisionKeepsTheOldPlan() async throws {
        let plan = try MacroLoaderV2Data.storedPlan(rounds: [MacroLoaderV2Data.earlierRound])
        let store = MemoryStore(plan)
        let provider = try makeProvider(failure: PlanAPIError.planUnavailable(reason: "timeout"))
        let loader = makeLoader(store: store, provider: provider)

        let revised = await loader.revise(feedback: "Mehr Laufen", snapshot: TestFixtures.snapshot)

        XCTAssertFalse(revised)
        XCTAssertEqual(provider.revisionRequests.count, 1)
        XCTAssertEqual(loader.plan, plan)
        XCTAssertEqual(loader.plan?.feedbackRounds, [MacroLoaderV2Data.earlierRound])
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(loader.error, PlanAPIError.planUnavailable(reason: "timeout").errorDescription)
        XCTAssertFalse(loader.isRevising)
    }

    func testLongFeedbackIsCutToTheLimit() async throws {
        let provider = try makeProvider()
        let plan = try MacroLoaderV2Data.storedPlan()
        let loader = makeLoader(store: MemoryStore(plan), provider: provider)
        let long = String(repeating: "a", count: MacroRevisionRequest.maxFeedbackLength + 200)

        await loader.revise(feedback: long, snapshot: TestFixtures.snapshot)

        XCTAssertEqual(provider.revisionRequests.first?.feedback.count, MacroRevisionRequest.maxFeedbackLength)
    }

    func testTheRevisionStampChangesWithEveryNewVersion() async throws {
        XCTAssertEqual(makeLoader(provider: nil).revisionStamp, "")

        let plan = try MacroLoaderV2Data.storedPlan()
        let provider = try makeProvider()
        let loader = makeLoader(store: MemoryStore(plan), provider: provider)
        let before = loader.revisionStamp
        XCTAssertEqual(before, "\(plan.generatedAt.timeIntervalSince1970)|0|0")

        await loader.revise(feedback: "Mehr Laufen", snapshot: TestFixtures.snapshot)

        XCTAssertNotEqual(loader.revisionStamp, before)
        XCTAssertTrue(loader.revisionStamp.hasSuffix("|1|0"))
    }

    // MARK: - Fortschreibung (P4)

    /// Der Plan aus dem Vertrag mit zwei vergangenen Wochen davor (14. und 21.09.), erstellt am 14.09.
    private func planWithPast() throws -> MacroPlanV2 {
        let plan = try MacroLoaderV2Data.storedPlan()
        let first = try XCTUnwrap(plan.weeks.first)
        let past = ["2026-09-14", "2026-09-21"].map { start in
            MacroWeekV2(weekStart: start, phase: first.phase, deload: false, focus: "Vorher", totalMinutes: first.totalMinutes, load: first.load, sports: first.sports, tests: [])
        }
        return MacroPlanV2(
            goalKey: plan.goalKey, goalDay: plan.goalDay, generatedAt: TestFixtures.date(daysAgo: 16, hour: 8),
            rationale: plan.rationale, weeks: past + plan.weeks
        )
    }

    func testTheScheduledReviewIsDueTwoWeeksAfterTheLastOne() throws {
        let plan = try planWithPast()
        let loader = makeLoader(store: MemoryStore(plan), provider: nil)
        XCTAssertEqual(loader.nextReviewWeekStart, "2026-09-28")
        XCTAssertTrue(loader.reviewDue)
        XCTAssertEqual(loader.pendingReviewReason(pause: nil), .scheduled)
        XCTAssertEqual(loader.reviewedPastWeekStarts, ["2026-09-14", "2026-09-21"])

        var reviewed = plan
        reviewed.reviews = [MacroReview(reviewedAt: TestFixtures.now, weekStart: "2026-09-28", reason: .scheduled, summary: "", changes: [])]
        let after = makeLoader(store: MemoryStore(reviewed), provider: nil)
        XCTAssertEqual(after.nextReviewWeekStart, "2026-10-12")
        XCTAssertFalse(after.reviewDue)
        XCTAssertNil(after.pendingReviewReason(pause: nil))
        let pause = PauseReport(kind: .sick, from: "2026-09-20", to: "2026-09-27", reportedAt: TestFixtures.now)
        XCTAssertEqual(after.pendingReviewReason(pause: pause), .pause)

        // Ein frischer Plan ist noch nicht dran.
        XCTAssertFalse(makeLoader(store: MemoryStore(try MacroLoaderV2Data.storedPlan()), provider: nil).reviewDue)
    }

    func testReviewSendsPlanAndActualAndKeepsPastAndRunningWeeks() async throws {
        let plan = try planWithPast()
        let store = MemoryStore(plan)
        let provider = try makeProvider()
        let loader = makeLoader(store: store, provider: provider)
        let swim = TestFixtures.workout(.swim, daysAgo: 12, minutes: 45, meters: 2_000)
        let run = TestFixtures.workout(.run, daysAgo: 8, minutes: 30, meters: 5_000)

        let review = try XCTUnwrap(await loader.reviewIfDue(snapshot: TestFixtures.snapshot, workouts: [swim, run], pause: nil))

        XCTAssertEqual(review.reason, .scheduled)
        XCTAssertEqual(review.weekStart, "2026-09-28")
        XCTAssertEqual(review.summary, "Schwimmen 96 % erfüllt, Radfahren 88 %, Laufen 70 %. In der zweiten Woche fielen zwei Läufe aus.")
        let request = try XCTUnwrap(provider.reviewRequests.first)
        XCTAssertEqual(request.reason, .scheduled)
        XCTAssertNil(request.pause)
        XCTAssertEqual(request.actual.map(\.weekStart), ["2026-09-14", "2026-09-21"])
        XCTAssertEqual(request.actual[0].amount(of: .swim), 2_000)
        XCTAssertEqual(request.actual[1].amount(of: .run), 30)

        let stored = try XCTUnwrap(store.stored)
        XCTAssertEqual(stored.reviews, [review])
        XCTAssertEqual(stored.generatedAt, plan.generatedAt)
        XCTAssertEqual(stored.week(starting: "2026-09-14")?.focus, "Vorher")
        XCTAssertEqual(stored.week(starting: "2026-09-28"), plan.week(starting: "2026-09-28"), "laufende Woche bleibt")
        let reviewed = try MacroLoaderV2Data.response("plan-v2-review-response.json")
        XCTAssertEqual(stored.week(starting: "2026-10-05"), reviewed.plan.weeks.first { $0.weekStart == "2026-10-05" })
        XCTAssertFalse(loader.reviewDue)

        // Höchstens einmal am Tag je Anlass.
        XCTAssertNil(await loader.reviewIfDue(snapshot: TestFixtures.snapshot, workouts: [], pause: nil))
        XCTAssertEqual(provider.reviewRequests.count, 1)
    }

    func testAFailedReviewKeepsThePlanAndTriesAgainOnlyTomorrow() async throws {
        let plan = try planWithPast()
        let provider = try makeProvider(failure: PlanAPIError.planUnavailable(reason: "timeout"))
        let reviewMarker = MemoryMarker()
        let loader = makeLoader(store: MemoryStore(plan), provider: provider, reviewMarker: reviewMarker)

        XCTAssertNil(await loader.reviewIfDue(snapshot: TestFixtures.snapshot, workouts: [], pause: nil))
        XCTAssertNil(await loader.reviewIfDue(snapshot: TestFixtures.snapshot, workouts: [], pause: nil))

        XCTAssertEqual(provider.reviewRequests.count, 1)
        XCTAssertEqual(loader.plan, plan)
        XCTAssertNotNil(loader.error)
        XCTAssertFalse(loader.isReviewing)
    }

    func testFeedbackOnceAfterANewPlanAndOnceAfterEachReview() async throws {
        let provider = try makeProvider()
        let plan = try MacroLoaderV2Data.storedPlan()
        XCTAssertTrue(plan.canGiveFeedback)
        let loader = makeLoader(store: MemoryStore(plan), provider: provider)

        XCTAssertTrue(await loader.revise(feedback: "Mehr Laufen", snapshot: TestFixtures.snapshot))
        XCTAssertEqual(loader.plan?.canGiveFeedback, false)
        XCTAssertFalse(await loader.revise(feedback: "Noch mehr", snapshot: TestFixtures.snapshot))
        XCTAssertEqual(provider.revisionRequests.count, 1)
        XCTAssertNotNil(loader.error)

        var reviewed = try XCTUnwrap(loader.plan)
        reviewed.reviews = [MacroReview(reviewedAt: TestFixtures.now.addingTimeInterval(60), weekStart: "2026-09-28", reason: .scheduled, summary: "", changes: [])]
        XCTAssertTrue(reviewed.canGiveFeedback)
    }

    func testActualWeeksUseThePlanUnitAndFindTwoWeakWeeks() throws {
        let calculator = MacroActualCalculator(calendar: TestFixtures.utc)
        let swim = TestFixtures.workout(.swim, daysAgo: 12, minutes: 45, meters: 2_000)
        let bike = TestFixtures.workout(.bike, daysAgo: 11, minutes: 90, meters: 40_000)
        let actual = calculator.actualWeeks(["2026-09-14", "2026-09-21"], workouts: [swim, bike, swim])
        XCTAssertEqual(actual[0].sports, [.init(sport: .swim, amount: 2_000, sessions: 1), .init(sport: .bike, amount: 90, sessions: 1)])
        XCTAssertEqual(actual[1].sports, [])

        let plan = try planWithPast()
        // Laufen geplant, aber in beiden Wochen nichts gelaufen; Schwimmen in der zweiten Woche auch nicht.
        let weak = calculator.lowComplianceSports(plan: plan, actual: actual, currentWeekStart: "2026-09-28")
        XCTAssertTrue(weak.contains(.run))
        XCTAssertTrue(weak.contains(.swim))
        XCTAssertEqual(MacroActualCalculator.percent(planned: 4_000, actual: 3_800), 95)
        XCTAssertNil(MacroActualCalculator.percent(planned: 0, actual: 10))
        // Ohne zwei vergangene Wochen kein Vorschlag.
        XCTAssertEqual(calculator.lowComplianceSports(plan: try MacroLoaderV2Data.storedPlan(), actual: [], currentWeekStart: "2026-09-28"), [])
    }

    func testPauseReportsTriggerOnceFromSevenDays() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PauseTests-\(UUID().uuidString)"))
        let store = UserDefaultsPauseReportStore(defaults: defaults)
        XCTAssertNil(store.pendingReviewReport(calendar: TestFixtures.utc))

        let short = PauseReport(kind: .vacation, from: "2026-09-21", to: "2026-09-26", reportedAt: TestFixtures.now)
        XCTAssertEqual(short.days(calendar: TestFixtures.utc), 6)
        store.setReport(short)
        XCTAssertNil(store.pendingReviewReport(calendar: TestFixtures.utc))

        let week = PauseReport(kind: .sick, from: "2026-09-21", to: "2026-09-27", reportedAt: TestFixtures.now)
        store.setReport(week)
        XCTAssertEqual(store.pendingReviewReport(calendar: TestFixtures.utc), week)
        store.markReviewed(week.id)
        XCTAssertNil(store.pendingReviewReport(calendar: TestFixtures.utc))

        // Eine laufende Pause zählt sofort; eine mit Ende vor dem Anfang wird nicht gespeichert.
        let ongoing = PauseReport(kind: .injury, from: "2026-09-29", to: nil, reportedAt: TestFixtures.now)
        store.setReport(ongoing)
        XCTAssertEqual(store.pendingReviewReport(calendar: TestFixtures.utc), ongoing)
        store.setReport(PauseReport(kind: .other, from: "2026-09-29", to: "2026-09-20", reportedAt: TestFixtures.now))
        XCTAssertEqual(store.report(), ongoing)
        store.setReport(nil)
        XCTAssertNil(store.report())
    }
}
