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
    static func storedPlan(goalKey: String = MacroLoaderV2Data.sprintKey, rounds: [MacroFeedbackRound] = []) throws -> MacroPlanV2 {
        try macroResponse().macroPlan(goalKey: goalKey, feedbackRounds: rounds)
    }

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
        marker: MemoryMarker = MemoryMarker()
    ) -> MultiSportMacroLoader {
        MultiSportMacroLoader(
            store: store,
            planProvider: { provider },
            goal: goal,
            attemptMarker: marker,
            now: { TestFixtures.now },
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
        XCTAssertEqual(before, "\(plan.generatedAt.timeIntervalSince1970)|0")

        await loader.revise(feedback: "Mehr Laufen", snapshot: TestFixtures.snapshot)

        XCTAssertNotEqual(loader.revisionStamp, before)
        XCTAssertTrue(loader.revisionStamp.hasSuffix("|1"))
    }
}
