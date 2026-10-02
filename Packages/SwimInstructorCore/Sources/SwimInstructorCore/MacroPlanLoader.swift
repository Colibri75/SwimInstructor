import Foundation

/// Hält den Gesamtplan bis zum Zieltag: holt ihn vom Server, speichert ihn und erneuert ihn, wenn das
/// Ziel geändert wurde oder er abgelaufen ist. Absichtlich ohne SwiftUI, damit der Ablauf per Unit-Test
/// prüfbar ist.
@MainActor
public final class MacroPlanLoader: ObservableObject {
    @Published public private(set) var plan: MacroPlan?
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    /// Kein Token hinterlegt.
    @Published public private(set) var needsConfiguration = false

    private let store: MacroPlanStoring
    private let planProvider: @MainActor () -> MacroPlanProviding?
    private let goal: @MainActor () -> AthleteGoal
    private let attemptMarker: DailyRefreshMarking
    private let now: () -> Date
    private let calendar: Calendar
    private let weekCalendar: WeekCalendar

    /// - Parameters:
    ///   - planProvider: liefert den API-Client zur aktuellen Konfiguration, `nil` ohne Token.
    ///   - goal: das Ziel aus den Einstellungen, bei jedem Zugriff neu gelesen.
    public init(
        store: MacroPlanStoring,
        planProvider: @escaping @MainActor () -> MacroPlanProviding?,
        goal: @escaping @MainActor () -> AthleteGoal = { .default },
        attemptMarker: DailyRefreshMarking = UserDefaultsDailyRefreshMarker(key: "plan.lastMacroAttempt"),
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

    public var currentGoalKey: String { goal().key(calendar: calendar) }

    /// Gilt der gespeicherte Gesamtplan noch? Er muss zum eingestellten Ziel gehören und die laufende
    /// Woche enthalten.
    public var isCurrent: Bool {
        guard let plan else { return false }
        return plan.goalKey == currentGoalKey && plan.week(starting: currentWeekStart) != nil
    }

    /// Die laufende Woche des Gesamtplans.
    public var currentWeek: MacroWeek? { plan?.week(starting: currentWeekStart) }

    /// Die Wochen des Gesamtplans, in die die Tage `dates` fallen, ohne Doppelte. Das geht mit der
    /// Anfrage für die nächsten sieben Tage an den Server.
    public func weeks(overlapping dates: [String]) -> [MacroWeek] {
        guard let plan else { return [] }
        var seen = Set<String>()
        var result: [MacroWeek] = []
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

    // MARK: - Erneuern

    /// Holt den Gesamtplan, wenn er fehlt, zu einem anderen Ziel gehört oder abgelaufen ist, aber höchstens
    /// einmal am Tag je Ziel (ein Fehlschlag soll nicht bei jedem Öffnen einen Claude-Aufruf kosten).
    public func ensureCurrent(snapshot: AthleteStateSnapshot) async {
        guard !isCurrent else { return }
        let marker = "\(todayKey)|\(currentGoalKey)"
        guard attemptMarker.lastDay() != marker else { return }
        attemptMarker.setLastDay(marker)
        await regenerate(snapshot: snapshot)
    }

    /// Berechnet den Gesamtplan neu (Knopf in der App). Scheitert es, bleibt der bisherige stehen.
    @discardableResult
    public func regenerate(snapshot: AthleteStateSnapshot) async -> Bool {
        guard !isLoading else { return false }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return false
        }
        needsConfiguration = false

        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await provider.fetchMacroPlan(MacroPlanRequest(snapshot: snapshot, today: todayKey))
            let fresh = response.macroPlan(goalKey: currentGoalKey)
            plan = fresh
            // Speichern ist Komfort; scheitert es, ist der Plan im Speicher trotzdem da.
            try? store.save(fresh)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
