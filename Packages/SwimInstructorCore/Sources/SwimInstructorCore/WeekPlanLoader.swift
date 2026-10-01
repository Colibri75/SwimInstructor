import Foundation

/// Steuert den Wochen-Tab: Wochenpläne vom Server holen, Änderungen des Athleten anwenden, alles auf
/// dem Gerät speichern. Absichtlich ohne SwiftUI, damit der Ablauf per Unit-Test prüfbar ist.
@MainActor
public final class WeekPlanLoader: ObservableObject {
    /// Zustand und Einheiten, aus denen eine Planung entsteht (kommt vom Heute-Bildschirm).
    public struct PlanningContext {
        public let snapshot: AthleteStateSnapshot
        public let workouts: [SwimWorkout]

        public init(snapshot: AthleteStateSnapshot, workouts: [SwimWorkout]) {
            self.snapshot = snapshot
            self.workouts = workouts
        }
    }

    /// So viele Wochen hebt die App auf.
    public static let retainedWeeks = 8

    @Published public private(set) var weeks: [WeekPlan]
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    /// Kein Token hinterlegt.
    @Published public private(set) var needsConfiguration = false
    /// Die Woche, die der Wochen-Tab zeigt (Montag, `yyyy-MM-dd`).
    @Published public var selectedWeekStart: String

    /// Liefert Zustand und Einheiten; wird nach dem Anlegen gesetzt, weil es vom Heute-Bildschirm abhängt.
    public var contextProvider: @MainActor () -> PlanningContext? = { nil }

    private let store: WeekPlanStoring
    private let planProvider: @MainActor () -> WeekPlanProviding?
    private let now: () -> Date
    private let weekCalendar: WeekCalendar
    private let calendar: Calendar

    /// - Parameter planProvider: liefert den API-Client zur aktuellen Konfiguration, `nil` ohne Token.
    public init(
        store: WeekPlanStoring,
        planProvider: @escaping @MainActor () -> WeekPlanProviding?,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.planProvider = planProvider
        self.now = now
        self.calendar = calendar
        self.weekCalendar = WeekCalendar(calendar: calendar)
        self.weeks = store.load()
        self.selectedWeekStart = WeekCalendar(calendar: calendar).weekStart(containing: now())
    }

    // MARK: - Lesen

    public var todayKey: String { PlanFormatting.isoDay(now(), calendar: calendar) }

    public var currentWeekStart: String { weekCalendar.weekStart(containing: now()) }

    public func week(starting weekStart: String) -> WeekPlan? {
        weeks.first { $0.weekStart == weekStart }
    }

    public var selectedWeek: WeekPlan? { week(starting: selectedWeekStart) }

    /// Der Eintrag des Wochenplans für heute, `nil` ohne Plan für diesen Tag.
    public var todayEntry: WeekDayPlan? {
        week(starting: currentWeekStart)?.day(on: todayKey)
    }

    /// Die Vorgabe für den Tagesplan (geht an den Server), `nil` ohne Wochenplan.
    public var todayTarget: DayPlanTarget? { todayEntry?.target }

    /// Eine Woche lässt sich planen, solange sie nicht ganz vorbei ist.
    public func canPlan(weekStarting weekStart: String) -> Bool {
        weekStart >= currentWeekStart
    }

    /// Ab wann in dieser Woche geplant wird: heute in der laufenden, der Montag in einer kommenden Woche.
    public func firstPlannedDate(forWeekStarting weekStart: String) -> String {
        max(todayKey, weekStart)
    }

    /// Einen Tag der gezeigten Woche ändern lässt sich ab heute.
    public func isEditable(_ date: String) -> Bool { date >= todayKey }

    // MARK: - Planen

    /// Plant die Woche (oder, in der laufenden Woche, den Rest ab heute) neu. Tage ohne Zeit bleiben
    /// Ruhetage, schon Geschwommenes zählt zum Wochenumfang.
    public func plan(weekStarting weekStart: String, wishes: String? = nil) async {
        guard !isLoading else { return }
        guard canPlan(weekStarting: weekStart) else {
            error = "Eine vergangene Woche lässt sich nicht mehr planen."
            return
        }
        guard let context = contextProvider() else {
            error = "Die Health-Daten sind noch nicht geladen. Öffne zuerst den Tab Heute."
            return
        }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return
        }
        needsConfiguration = false

        let fromDate = firstPlannedDate(forWeekStarting: weekStart)
        let existing = week(starting: weekStart)
        let request = WeekPlanRequest(
            snapshot: context.snapshot,
            weekStart: weekStart,
            fromDate: fromDate,
            today: todayKey,
            unavailableDates: (existing?.days ?? []).filter { $0.isUnavailable && $0.date >= fromDate }.map(\.date),
            swumThisWeek: swumDays(weekStarting: weekStart, before: fromDate, workouts: context.workouts),
            wishes: wishes
        )

        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await provider.fetchWeekPlan(request)
            let merged = WeekPlanEditor.merge(existing: existing, generated: response.weekPlan, fromDate: fromDate)
            replace(merged)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Schon geschwommene Meter je Tag, vom Montag bis vor `fromDate`.
    func swumDays(weekStarting weekStart: String, before fromDate: String, workouts: [SwimWorkout]) -> [SwumDay] {
        var meters: [String: Double] = [:]
        for workout in workouts where workout.startDate <= now() {
            let key = PlanFormatting.isoDay(workout.startDate, calendar: calendar)
            guard key >= weekStart, key < fromDate else { continue }
            meters[key, default: 0] += workout.totalDistanceMeters ?? 0
        }
        return meters.keys.sorted().map { SwumDay(date: $0, meters: meters[$0] ?? 0) }
    }

    // MARK: - Ändern

    public func markUnavailable(_ date: String) {
        edit { WeekPlanEditor.markUnavailable($0, date: date) }
    }

    public func clearUnavailable(_ date: String) {
        edit { WeekPlanEditor.clearUnavailable($0, date: date) }
    }

    public func setRest(_ date: String) {
        edit { WeekPlanEditor.setRest($0, date: date) }
    }

    public func setDistance(_ date: String, meters: Int) {
        edit { WeekPlanEditor.setDistance($0, date: date, meters: meters) }
    }

    public func swapDays(_ first: String, _ second: String) {
        edit { WeekPlanEditor.swap($0, first, second) }
    }

    public func moveToRestDay(from source: String, to target: String) {
        edit { WeekPlanEditor.moveToRestDay($0, from: source, to: target) }
    }

    /// Wendet eine Änderung auf die gezeigte Woche an und speichert. Ohne Plan für die Woche passiert nichts.
    private func edit(_ change: (WeekPlan) -> WeekPlan) {
        guard let current = selectedWeek else { return }
        let changed = change(current)
        guard changed != current else { return }
        replace(changed)
    }

    private func replace(_ plan: WeekPlan) {
        var updated = weeks.filter { $0.weekStart != plan.weekStart }
        updated.append(plan)
        updated.sort { $0.weekStart < $1.weekStart }
        if updated.count > Self.retainedWeeks {
            updated.removeFirst(updated.count - Self.retainedWeeks)
        }
        weeks = updated
        // Speichern ist Komfort; scheitert es, ist der Plan im Speicher trotzdem da.
        try? store.save(updated)
    }

    // MARK: - Woche wechseln

    /// Eine Woche vor oder zurück, höchstens vier Wochen zurück und eine Woche voraus.
    public func shiftSelectedWeek(by weeksDelta: Int) {
        let current = currentWeekStart
        guard let target = weekCalendar.addingDays(weeksDelta * 7, to: selectedWeekStart),
              let earliest = weekCalendar.addingDays(-28, to: current),
              let latest = weekCalendar.addingDays(7, to: current),
              target >= earliest, target <= latest else { return }
        selectedWeekStart = target
    }
}
