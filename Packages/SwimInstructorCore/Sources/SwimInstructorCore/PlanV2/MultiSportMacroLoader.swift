import Foundation

/// Hält den Gesamtplan v2 bis zum Zieltag: holt ihn vom Server, speichert ihn, erneuert ihn bei geändertem Ziel und
/// überarbeitet ihn nach dem Feedback des Athleten. Für alle Sportarten des Ziels.
/// Absichtlich ohne SwiftUI.
@MainActor
public final class MultiSportMacroLoader: ObservableObject {
    @Published public private(set) var plan: MacroPlanV2?
    @Published public private(set) var isLoading = false
    /// Eine Überarbeitung nach Feedback läuft.
    @Published public private(set) var isRevising = false
    /// Eine Fortschreibung läuft (P4).
    @Published public private(set) var isReviewing = false
    @Published public private(set) var error: String?
    /// Kein Token hinterlegt.
    @Published public private(set) var needsConfiguration = false

    public var testSettingsProvider: @MainActor () -> TestSettings? = { nil }
    /// Bestätigte Leistungswerte seit einem Zeitpunkt (dem letzten Stand des Plans), für die Fortschreibung.
    public var performanceChangesProvider: @MainActor (Date) -> [PerformanceChange] = { _ in [] }

    private let store: MacroPlanV2Storing
    private let planProvider: @MainActor () -> MacroPlanV2Providing?
    private let goal: @MainActor () -> TrainingGoal
    private let goalVersion: (@MainActor () -> Int)?
    private let attemptMarker: DailyRefreshMarking
    private let reviewMarker: DailyRefreshMarking
    private let now: () -> Date
    private let calendar: Calendar
    private let weekCalendar: WeekCalendar

    /// - Parameters:
    ///   - planProvider: liefert den API-Client zur aktuellen Konfiguration, `nil` ohne Token.
    ///   - goal: das Ziel aus den Einstellungen, bei jedem Zugriff neu gelesen.
    ///   - goalVersion: die Zielversion (P3). Mit ihr gehört ein Gesamtplan zu einer Version statt zu `planKey`, und eine
    ///     Feinjustierung des Ziels lässt ihn stehen.
    public init(
        store: MacroPlanV2Storing,
        planProvider: @escaping @MainActor () -> MacroPlanV2Providing?,
        goal: @escaping @MainActor () -> TrainingGoal,
        goalVersion: (@MainActor () -> Int)? = nil,
        attemptMarker: DailyRefreshMarking = UserDefaultsDailyRefreshMarker(key: "plan.lastMacroAttemptV2"),
        reviewMarker: DailyRefreshMarking = UserDefaultsDailyRefreshMarker(key: "plan.lastMacroReviewAttemptV2"),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.planProvider = planProvider
        self.goal = goal
        self.goalVersion = goalVersion
        self.attemptMarker = attemptMarker
        self.reviewMarker = reviewMarker
        self.now = now
        self.calendar = calendar
        self.weekCalendar = WeekCalendar(calendar: calendar)
        self.plan = store.load()
    }

    // MARK: - Lesen

    public var todayKey: String { PlanFormatting.isoDay(now(), calendar: calendar) }

    public var currentWeekStart: String { weekCalendar.weekStart(containing: now()) }

    public var currentGoalKey: String {
        guard let goalVersion else { return goal().planKey(calendar: calendar) }
        return "goal-v\(goalVersion())"
    }

    /// Gilt der gespeicherte Gesamtplan noch? Er muss zum eingestellten Ziel gehören und die laufende Woche enthalten.
    /// Ein Plan von vor der Zielversion zählt, solange er zu `planKey` des Ziels passt.
    public var isCurrent: Bool {
        guard let plan else { return false }
        return belongsToGoal(plan) && plan.week(starting: currentWeekStart) != nil
    }

    private func belongsToGoal(_ plan: MacroPlanV2) -> Bool {
        plan.goalKey == currentGoalKey || (goalVersion != nil && plan.goalKey == goal().planKey(calendar: calendar))
    }

    /// Die laufende Woche des Gesamtplans.
    public var currentWeek: MacroWeekV2? { plan?.week(starting: currentWeekStart) }

    /// Die Wochen ab der laufenden.
    public var upcomingWeeks: [MacroWeekV2] { plan?.weeks(from: currentWeekStart) ?? [] }

    /// Die Wochen des Gesamtplans, in die die Tage `dates` fallen, ohne Doppelte. Sie gehen mit der Anfrage für die
    /// nächsten sieben Tage an den Server.
    public func weeks(overlapping dates: [String]) -> [MacroWeekV2] {
        guard let plan else { return [] }
        var seen = Set<String>()
        var result: [MacroWeekV2] = []
        for date in dates {
            guard let day = weekCalendar.date(from: date) else { continue }
            let start = weekCalendar.weekStart(containing: day)
            if seen.insert(start).inserted, let week = plan.week(starting: start) {
                result.append(week)
            }
        }
        return result
    }

    /// Wochen bis zum Zieltag (angebrochene zählen), 0 danach.
    public var weeksUntilGoal: Int {
        guard let plan, let goalDate = weekCalendar.date(from: plan.goalDay), let today = weekCalendar.date(from: todayKey) else { return 0 }
        let days = calendar.dateComponents([.day], from: today, to: goalDate).day ?? 0
        return max((days + 6) / 7, 0)
    }

    /// Ein Merkmal des Plans, das sich mit jeder neuen Fassung ändert. Der Plan der nächsten sieben Tage nutzt es, um
    /// sich nach einer Überarbeitung neu abzustimmen.
    public var revisionStamp: String {
        guard let plan else { return "" }
        return "\(plan.generatedAt.timeIntervalSince1970)|\(plan.feedbackRounds.count)|\(plan.reviews.count)"
    }

    // MARK: - Erneuern

    /// Holt den Gesamtplan, wenn er fehlt, zu einem anderen Ziel gehört oder abgelaufen ist, aber höchstens einmal am
    /// Tag je Ziel (ein Fehlschlag soll nicht bei jedem Öffnen einen Claude-Aufruf kosten).
    public func ensureCurrent(snapshot: AthleteStateSnapshot) async {
        // Umzug auf die Zielversion: Ein Plan zu `planKey` bekommt die Version, damit eine spätere Feinjustierung ihn
        // nicht ungültig macht.
        if var current = plan, current.goalKey != currentGoalKey, belongsToGoal(current) {
            current.goalKey = currentGoalKey
            store(current)
        }
        guard !isCurrent else { return }
        let marker = "\(todayKey)|\(currentGoalKey)"
        guard attemptMarker.lastDay() != marker else { return }
        attemptMarker.setLastDay(marker)
        await regenerate(snapshot: snapshot)
    }

    /// Berechnet den Gesamtplan neu. Die Feedback-Runden beginnen von vorn. Die laufende Woche des bisherigen Plans
    /// bleibt, damit die nächsten sieben Tage nicht unter dem Athleten wegrutschen. Scheitert es, bleibt der bisherige
    /// stehen.
    @discardableResult
    public func regenerate(snapshot: AthleteStateSnapshot) async -> Bool {
        guard !isLoading, !isRevising, !isReviewing else { return false }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return false
        }
        needsConfiguration = false

        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await provider.fetchMacroPlanV2(
                MacroPlanV2Request(snapshot: snapshot, today: todayKey, testSettings: testSettingsProvider())
            )
            store(keepingCurrentWeek(response.macroPlan(goalKey: currentGoalKey)))
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Überarbeitet den Gesamtplan nach dem Feedback des Athleten ("weniger Laufen im Winter"). Der Server bekommt die
    /// bisherigen Runden mit; die neue Runde mit der Liste der Änderungen hängt danach am Plan. Scheitert es, bleibt der
    /// bisherige Plan stehen.
    @discardableResult
    public func revise(feedback: String, snapshot: AthleteStateSnapshot) async -> Bool {
        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Schreib zuerst, was sich am Plan ändern soll."
            return false
        }
        guard let current = plan else {
            error = "Es gibt noch keinen Gesamtplan."
            return false
        }
        guard !isLoading, !isRevising, !isReviewing else { return false }
        guard current.canGiveFeedback else {
            error = "Feedback gibt es einmal nach einem neuen Plan und einmal zu jeder Fortschreibung."
            return false
        }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return false
        }
        needsConfiguration = false

        isRevising = true
        defer { isRevising = false }
        do {
            let response = try await provider.reviseMacroPlan(MacroRevisionRequest(
                snapshot: snapshot,
                today: todayKey,
                plan: current,
                feedback: String(trimmed.prefix(MacroRevisionRequest.maxFeedbackLength)),
                testSettings: testSettingsProvider()
            ))
            let round = MacroFeedbackRound(
                feedback: response.feedback ?? String(trimmed.prefix(MacroRevisionRequest.maxFeedbackLength)),
                changes: response.changes ?? [],
                adjustments: response.adjustments,
                revisedAt: now()
            )
            var revisedPlan = keepingPastWeeks(of: current, in: response.macroPlan(goalKey: current.goalKey, feedbackRounds: current.feedbackRounds + [round]))
            revisedPlan.generatedAt = current.generatedAt
            revisedPlan.reviews = current.reviews
            store(revisedPlan)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: - Fortschreibung (P4)

    /// Ist die regelmäßige Fortschreibung fällig? Ab dem Montag zwei Wochen nach der letzten.
    public var reviewDue: Bool {
        guard let plan, isCurrent else { return false }
        return currentWeekStart >= plan.nextReviewWeekStart(calendar: calendar)
    }

    /// Montag der nächsten regelmäßigen Fortschreibung.
    public var nextReviewWeekStart: String? { plan?.nextReviewWeekStart(calendar: calendar) }

    /// So weit zurück gehen Plan und Ist an die Fortschreibung (4 Wochen; Health liefert 8).
    public static let reviewLookbackDays = 28

    /// Die vergangenen Wochen des Plans, die an die Fortschreibung gehen und im Plan-Tab mit Ist stehen.
    public var reviewedPastWeekStarts: [String] {
        guard let plan, let start = lookbackStart else { return [] }
        return plan.weeks.map(\.weekStart).filter { $0 >= start && $0 < currentWeekStart }
    }

    private var lookbackStart: String? {
        guard let current = weekCalendar.date(from: currentWeekStart),
              let start = calendar.date(byAdding: .day, value: -Self.reviewLookbackDays, to: current) else { return nil }
        return weekCalendar.weekStart(containing: start)
    }

    /// Der Anlass für eine Fortschreibung jetzt: eine gemeldete Pause geht vor, sonst die regelmäßige.
    public func pendingReviewReason(pause: PauseReport?) -> MacroReviewReason? {
        guard plan != nil, isCurrent else { return nil }
        if pause != nil { return .pause }
        return reviewDue ? .scheduled : nil
    }

    /// Schreibt fort, wenn es fällig ist (regelmäßig oder nach einer gemeldeten Pause), höchstens einmal am Tag je Anlass.
    /// Gibt die neue Fortschreibung zurück, sonst `nil`.
    @discardableResult
    public func reviewIfDue(snapshot: AthleteStateSnapshot, workouts: [Workout], pause: PauseReport?) async -> MacroReview? {
        guard let reason = pendingReviewReason(pause: pause) else { return nil }
        let marker = "\(todayKey)|\(reason.rawValue)|\(currentGoalKey)"
        guard reviewMarker.lastDay() != marker else { return nil }
        reviewMarker.setLastDay(marker)
        return await review(reason: reason, snapshot: snapshot, workouts: workouts, pause: reason == .pause ? pause : nil)
    }

    /// Schreibt den Gesamtplan fort: Plan gegen Ist der letzten Wochen, Anlass, optional Pause und Feedback. Die
    /// vergangenen Wochen und die laufende Woche bleiben, wie sie sind; die Antwort ersetzt die Wochen danach. Scheitert
    /// es, bleibt der bisherige Plan stehen.
    @discardableResult
    public func review(
        reason: MacroReviewReason,
        snapshot: AthleteStateSnapshot,
        workouts: [Workout],
        pause: PauseReport? = nil,
        feedback: String? = nil
    ) async -> MacroReview? {
        guard let current = plan else {
            error = "Es gibt noch keinen Gesamtplan."
            return nil
        }
        guard !isLoading, !isRevising, !isReviewing else { return nil }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return nil
        }
        needsConfiguration = false

        isReviewing = true
        defer { isReviewing = false }
        let actual = MacroActualCalculator(calendar: calendar).actualWeeks(reviewedPastWeekStarts, workouts: workouts)
        do {
            let response = try await provider.reviewMacroPlan(MacroReviewRequest(
                snapshot: snapshot,
                today: todayKey,
                plan: current,
                planFrom: lookbackStart ?? currentWeekStart,
                actual: actual,
                reason: reason,
                pause: pause,
                feedback: feedback,
                performanceChanges: performanceChangesProvider(current.lastRevisionDate),
                testSettings: testSettingsProvider()
            ))
            let review = MacroReview(
                reviewedAt: now(),
                weekStart: currentWeekStart,
                reason: response.reason ?? reason,
                summary: response.summary ?? "",
                changes: response.changes ?? [],
                adjustments: response.adjustments,
                feedback: response.feedback
            )
            let fresh = response.macroPlan(goalKey: current.goalKey, feedbackRounds: current.feedbackRounds)
            var merged = keepingPastWeeks(of: current, in: keepingCurrentWeek(fresh))
            merged.generatedAt = current.generatedAt
            merged.reviews = current.reviews + [review]
            store(merged)
            error = nil
            return review
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Der neue Plan mit den vergangenen Wochen des bisherigen (Plan gegen Ist bleibt sichtbar).
    private func keepingPastWeeks(of old: MacroPlanV2, in fresh: MacroPlanV2) -> MacroPlanV2 {
        let past = old.weeks.filter { $0.weekStart < currentWeekStart }
        var merged = fresh
        merged.weeks = (past + fresh.weeks.filter { $0.weekStart >= currentWeekStart }).sorted { $0.weekStart < $1.weekStart }
        return merged
    }

    /// Der neue Plan mit der laufenden Woche des bisherigen, falls es sie gibt.
    private func keepingCurrentWeek(_ fresh: MacroPlanV2) -> MacroPlanV2 {
        guard let week = plan?.week(starting: currentWeekStart) else { return fresh }
        var merged = fresh
        merged.weeks = (fresh.weeks.filter { $0.weekStart != week.weekStart } + [week]).sorted { $0.weekStart < $1.weekStart }
        return merged
    }

    private func store(_ fresh: MacroPlanV2) {
        plan = fresh
        // Speichern ist Komfort; scheitert es, ist der Plan im Speicher trotzdem da.
        try? store.save(fresh)
    }
}
