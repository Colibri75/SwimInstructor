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

    /// Das Equipment des Athleten für die Anfrage (Rohwerte); `nil`: keine Angabe.
    public var equipmentProvider: @MainActor () -> [String]? = { nil }

    private let store: WeekPlanStoring
    private let dailyMarker: DailyRefreshMarking
    private let planProvider: @MainActor () -> WeekPlanProviding?
    private let now: () -> Date
    private let weekCalendar: WeekCalendar
    private let calendar: Calendar

    /// - Parameter planProvider: liefert den API-Client zur aktuellen Konfiguration, `nil` ohne Token.
    public init(
        store: WeekPlanStoring,
        planProvider: @escaping @MainActor () -> WeekPlanProviding?,
        dailyMarker: DailyRefreshMarking = UserDefaultsDailyRefreshMarker(key: "plan.lastWeekRefresh"),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.dailyMarker = dailyMarker
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

    /// Einen Tag der gezeigten Woche ändern lässt sich ab heute.
    public func isEditable(_ date: String) -> Bool { date >= todayKey }

    // MARK: - Planen

    /// So viele Tage plant der rollende Plan voraus.
    public static let windowDays = 7

    /// Was der Gesamtplan für die Wochen der Tage `dates` vorgibt; wird nach dem Anlegen gesetzt, weil der
    /// Gesamtplan woanders liegt.
    public var macroProvider: @MainActor ([String]) -> [MacroWeek] = { _ in [] }

    /// Plant die nächsten sieben Tage ab heute neu, abgestimmt auf Zustand, Trainingsstand, die Vorwoche und
    /// den Gesamtplan. Tage ohne Zeit bleiben Ruhetage. Liefert `true`, wenn der Plan erneuert wurde.
    @discardableResult
    public func planNextDays(wishes: String? = nil) async -> Bool {
        guard !isLoading else { return false }
        guard let context = contextProvider() else {
            error = "Die Health-Daten sind noch nicht geladen. Öffne zuerst den Tab Heute."
            return false
        }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return false
        }
        needsConfiguration = false

        let fromDate = todayKey
        let dates = weekCalendar.dates(from: fromDate, count: Self.windowDays)
        let through = dates.last ?? fromDate
        let unavailable = weeks.flatMap(\.days).filter { $0.isUnavailable && dates.contains($0.date) }.map(\.date)
        let request = WeekPlanRequest(
            snapshot: context.snapshot,
            weekStart: nil,
            fromDate: fromDate,
            today: fromDate,
            unavailableDates: Array(Set(unavailable)).sorted(),
            swumThisWeek: [],
            wishes: wishes,
            equipment: equipmentProvider(),
            recentSwim: swumDays(from: weekCalendar.addingDays(-Self.windowDays, to: fromDate) ?? fromDate, before: fromDate, workouts: context.workouts),
            macroWeeks: macroProvider(dates)
        )

        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await provider.fetchWeekPlan(request)
            apply(response, fromDate: fromDate, through: through)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Einmal am Tag, beim ersten Öffnen: die nächsten sieben Tage neu auf Zustand, Stand und Vorwoche
    /// abstimmen. Schlägt es fehl (kein Netz, Budget), gilt der Tag nicht als erledigt, und das nächste
    /// Öffnen versucht es wieder. `stamp` gehört zum Tag-Vermerk: Ändert er sich (etwa mit dem Ziel), gilt
    /// der Tag wieder als offen.
    public func refreshDaily(wishes: String? = nil, stamp: String = "") async {
        let marker = "\(todayKey)|\(stamp)"
        guard dailyMarker.lastDay() != marker else { return }
        if await planNextDays(wishes: wishes) {
            dailyMarker.setLastDay(marker)
        }
    }

    /// Verteilt die Tage der Antwort auf ihre Kalenderwochen und führt sie mit den gespeicherten zusammen.
    private func apply(_ response: WeekPlanResponse, fromDate: String, through: String) {
        var byWeek: [String: [WeekDayPlan]] = [:]
        for day in response.plan.days {
            guard let date = weekCalendar.date(from: day.date) else { continue }
            byWeek[weekCalendar.weekStart(containing: date), default: []].append(day)
        }
        for (weekStart, days) in byWeek {
            let generated = WeekPlan(
                weekStart: weekStart,
                generatedAt: response.generatedAt,
                rationale: response.plan.rationale,
                adjustments: response.adjustments,
                wishes: response.wishes,
                days: days
            )
            replace(WeekPlanEditor.merge(existing: week(starting: weekStart), generated: generated, fromDate: fromDate, through: through))
        }
    }

    /// Schon geschwommene Meter je Tag, von `start` (einschließlich) bis vor `end`.
    func swumDays(from start: String, before end: String, workouts: [SwimWorkout]) -> [SwumDay] {
        var meters: [String: Double] = [:]
        for workout in workouts where workout.startDate <= now() {
            let key = PlanFormatting.isoDay(workout.startDate, calendar: calendar)
            guard key >= start, key < end else { continue }
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

/// Merkt, wann der Wochenplan oder der Gesamtplan zuletzt automatisch angepasst wurde ("einmal am Tag").
/// Der Wert besteht aus dem Tag und einem Zusatz.
public protocol DailyRefreshMarking {
    func lastDay() -> String?
    func setLastDay(_ marker: String)
}

public struct UserDefaultsDailyRefreshMarker: DailyRefreshMarking {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String) {
        self.defaults = defaults
        self.key = key
    }

    public func lastDay() -> String? {
        defaults.string(forKey: key)
    }

    public func setLastDay(_ marker: String) {
        defaults.set(marker, forKey: key)
    }
}

