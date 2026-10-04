import Foundation

/// Hält den Gesamtplan v2 bis zum Zieltag: holt ihn vom Server, speichert ihn, erneuert ihn bei geändertem Ziel und
/// überarbeitet ihn nach dem Feedback des Athleten. Wie `MacroPlanLoader`, für alle Sportarten des Ziels. Absichtlich
/// ohne SwiftUI.
@MainActor
public final class MultiSportMacroLoader: ObservableObject {
    @Published public private(set) var plan: MacroPlanV2?
    @Published public private(set) var isLoading = false
    /// Eine Überarbeitung nach Feedback läuft.
    @Published public private(set) var isRevising = false
    @Published public private(set) var error: String?
    /// Kein Token hinterlegt.
    @Published public private(set) var needsConfiguration = false

    public var testSettingsProvider: @MainActor () -> TestSettings? = { nil }

    private let store: MacroPlanV2Storing
    private let planProvider: @MainActor () -> MacroPlanV2Providing?
    private let goal: @MainActor () -> TrainingGoal
    private let attemptMarker: DailyRefreshMarking
    private let now: () -> Date
    private let calendar: Calendar
    private let weekCalendar: WeekCalendar

    /// - Parameters:
    ///   - planProvider: liefert den API-Client zur aktuellen Konfiguration, `nil` ohne Token.
    ///   - goal: das Ziel aus den Einstellungen, bei jedem Zugriff neu gelesen.
    public init(
        store: MacroPlanV2Storing,
        planProvider: @escaping @MainActor () -> MacroPlanV2Providing?,
        goal: @escaping @MainActor () -> TrainingGoal,
        attemptMarker: DailyRefreshMarking = UserDefaultsDailyRefreshMarker(key: "plan.lastMacroAttemptV2"),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.planProvider = planProvider
        self.goal = goal
        self.attemptMarker = attemptMarker
        self.now = now
        self.calendar = calendar
        self.weekCalendar = WeekCalendar(calendar: calendar)
        self.plan = store.load()
    }

    // MARK: - Lesen

    public var todayKey: String { PlanFormatting.isoDay(now(), calendar: calendar) }

    public var currentWeekStart: String { weekCalendar.weekStart(containing: now()) }

    public var currentGoalKey: String { goal().planKey(calendar: calendar) }

    /// Gilt der gespeicherte Gesamtplan noch? Er muss zum eingestellten Ziel gehören und die laufende Woche enthalten.
    public var isCurrent: Bool {
        guard let plan else { return false }
        return plan.goalKey == currentGoalKey && plan.week(starting: currentWeekStart) != nil
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
        return "\(plan.generatedAt.timeIntervalSince1970)|\(plan.feedbackRounds.count)"
    }

    // MARK: - Erneuern

    /// Holt den Gesamtplan, wenn er fehlt, zu einem anderen Ziel gehört oder abgelaufen ist, aber höchstens einmal am
    /// Tag je Ziel (ein Fehlschlag soll nicht bei jedem Öffnen einen Claude-Aufruf kosten).
    public func ensureCurrent(snapshot: AthleteStateSnapshot) async {
        guard !isCurrent else { return }
        let marker = "\(todayKey)|\(currentGoalKey)"
        guard attemptMarker.lastDay() != marker else { return }
        attemptMarker.setLastDay(marker)
        await regenerate(snapshot: snapshot)
    }

    /// Berechnet den Gesamtplan neu (Knopf in der App). Die Feedback-Runden beginnen von vorn. Scheitert es, bleibt der
    /// bisherige stehen.
    @discardableResult
    public func regenerate(snapshot: AthleteStateSnapshot) async -> Bool {
        guard !isLoading, !isRevising else { return false }
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
            store(response.macroPlan(goalKey: currentGoalKey))
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
        guard !isLoading, !isRevising else { return false }
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
            store(response.macroPlan(goalKey: current.goalKey, feedbackRounds: current.feedbackRounds + [round]))
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func store(_ fresh: MacroPlanV2) {
        plan = fresh
        // Speichern ist Komfort; scheitert es, ist der Plan im Speicher trotzdem da.
        try? store.save(fresh)
    }
}
