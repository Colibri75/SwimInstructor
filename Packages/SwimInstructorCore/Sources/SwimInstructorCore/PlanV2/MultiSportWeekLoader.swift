import Foundation

/// Steuert die nächsten sieben Tage in Plan v2: vom Server holen, Änderungen des Athleten anwenden, alles auf dem Gerät
/// speichern. Wie `WeekPlanLoader`, mit null bis zwei Einheiten je Tag über alle Sportarten. Absichtlich ohne SwiftUI.
@MainActor
public final class MultiSportWeekLoader: ObservableObject {
    /// Zustand und Einheiten aller Sportarten, aus denen eine Planung entsteht (kommt vom Heute-Bildschirm).
    public struct PlanningContext {
        public let snapshot: AthleteStateSnapshot
        public let workouts: [Workout]

        public init(snapshot: AthleteStateSnapshot, workouts: [Workout]) {
            self.snapshot = snapshot
            self.workouts = workouts
        }
    }

    /// So viele Kalenderwochen hebt die App auf.
    public static let retainedWeeks = 8
    /// So viele Tage plant der rollende Plan voraus.
    public static let windowDays = 7

    @Published public private(set) var weeks: [WeekPlanV2]
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    /// Kein Token hinterlegt.
    @Published public private(set) var needsConfiguration = false
    /// Die Woche, die der Plan-Tab zeigt (Montag, `yyyy-MM-dd`).
    @Published public var selectedWeekStart: String

    /// Liefert Zustand und Einheiten; wird nach dem Anlegen gesetzt, weil es vom Heute-Bildschirm abhängt.
    public var contextProvider: @MainActor () -> PlanningContext? = { nil }
    /// Das Equipment des Athleten (Rohwerte); `nil`: keine Angabe.
    public var equipmentProvider: @MainActor () -> [String]? = { nil }
    /// Was der Gesamtplan für die Wochen der Tage vorgibt.
    public var macroProvider: @MainActor ([String]) -> [MacroWeekV2] = { _ in [] }
    public var testSettingsProvider: @MainActor () -> TestSettings? = { nil }

    private let store: WeekPlanV2Storing
    private let dailyMarker: DailyRefreshMarking
    private let planProvider: @MainActor () -> WeekPlanV2Providing?
    private let registry: SportRegistry
    private let now: () -> Date
    private let weekCalendar: WeekCalendar
    private let calendar: Calendar

    /// - Parameter planProvider: liefert den API-Client zur aktuellen Konfiguration, `nil` ohne Token.
    public init(
        store: WeekPlanV2Storing,
        planProvider: @escaping @MainActor () -> WeekPlanV2Providing?,
        dailyMarker: DailyRefreshMarking = UserDefaultsDailyRefreshMarker(key: "plan.lastWeekRefreshV2"),
        registry: SportRegistry = .standard,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.dailyMarker = dailyMarker
        self.planProvider = planProvider
        self.registry = registry
        self.now = now
        self.calendar = calendar
        self.weekCalendar = WeekCalendar(calendar: calendar)
        self.weeks = store.load()
        self.selectedWeekStart = WeekCalendar(calendar: calendar).weekStart(containing: now())
    }

    // MARK: - Lesen

    public var todayKey: String { PlanFormatting.isoDay(now(), calendar: calendar) }

    public var currentWeekStart: String { weekCalendar.weekStart(containing: now()) }

    public func week(starting weekStart: String) -> WeekPlanV2? {
        weeks.first { $0.weekStart == weekStart }
    }

    public var selectedWeek: WeekPlanV2? { week(starting: selectedWeekStart) }

    /// Der geplante Tag `date`, egal in welcher Woche.
    public func day(on date: String) -> PlannedDay? {
        weekStart(of: date).flatMap { week(starting: $0) }?.day(on: date)
    }

    /// Der Eintrag für heute, `nil` ohne Plan für diesen Tag.
    public var todayEntry: PlannedDay? { day(on: todayKey) }

    /// Die Vorgabe für den Tagesplan (geht an den Server), `nil` ohne Plan für heute.
    public var todayTarget: DayTargetV2? { todayEntry?.target }

    /// Ändern lässt sich ein Tag ab heute.
    public func isEditable(_ date: String) -> Bool { date >= todayKey }

    /// Ob der Plan für `date` in dieser Sportart eine harte Einheit vorsah.
    public func plannedHard(on date: String, sport: SportID) -> Bool {
        day(on: date)?.sessions.contains { $0.sport == sport && $0.isHard } ?? false
    }

    /// Das bisherige Training von `start` bis vor `end` für die Anfrage, mit "hart" aus Plan und Puls.
    public func recentTraining(from start: String, before end: String, snapshot: AthleteStateSnapshot, workouts: [Workout]) -> [RecentTrainingEntry] {
        RecentTraining.entries(
            workouts: workouts.filter { $0.startDate <= now() },
            from: start,
            before: end,
            plannedHard: { [weak self] date, sport in self?.plannedHard(on: date, sport: sport) ?? false },
            maximumHeartRate: snapshot.performance?.athlete.first(where: { $0.metric == .maxHeartRate })?.value,
            registry: registry,
            calendar: calendar
        )
    }

    /// Das Training der sieben Tage vor heute und von heute, für den Tagesplan.
    public func recentTrainingForToday(snapshot: AthleteStateSnapshot, workouts: [Workout]) -> [RecentTrainingEntry] {
        let start = weekCalendar.addingDays(-Self.windowDays, to: todayKey) ?? todayKey
        let end = weekCalendar.addingDays(1, to: todayKey) ?? todayKey
        return recentTraining(from: start, before: end, snapshot: snapshot, workouts: workouts)
    }

    // MARK: - Planen

    /// Plant die nächsten sieben Tage ab heute neu, abgestimmt auf Zustand, bisheriges Training und Gesamtplan. Tage ohne
    /// Zeit bleiben Ruhetage. Liefert `true`, wenn der Plan erneuert wurde.
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
        let unavailable = Set(dates.filter { day(on: $0)?.isUnavailable == true })
        let request = WeekPlanV2Request(
            snapshot: context.snapshot,
            fromDate: fromDate,
            today: fromDate,
            unavailableDates: unavailable.sorted(),
            recentTraining: recentTraining(
                from: weekCalendar.addingDays(-Self.windowDays, to: fromDate) ?? fromDate,
                before: fromDate,
                snapshot: context.snapshot,
                workouts: context.workouts
            ),
            macroWeeks: macroProvider(dates),
            wishes: wishes,
            equipment: equipmentProvider(),
            testSettings: testSettingsProvider()
        )

        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await provider.fetchWeekPlanV2(request)
            apply(response, fromDate: fromDate, through: through)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Einmal am Tag, beim ersten Öffnen: die nächsten sieben Tage neu abstimmen. Schlägt es fehl, gilt der Tag nicht als
    /// erledigt. Ändert sich `stamp` (etwa mit dem Ziel oder dem Gesamtplan), gilt der Tag wieder als offen.
    public func refreshDaily(wishes: String? = nil, stamp: String = "") async {
        let marker = "\(todayKey)|\(stamp)"
        guard dailyMarker.lastDay() != marker else { return }
        if await planNextDays(wishes: wishes) {
            dailyMarker.setLastDay(marker)
        }
    }

    /// Verteilt die Tage der Antwort auf ihre Kalenderwochen und führt sie mit den gespeicherten zusammen.
    private func apply(_ response: WeekPlanV2Response, fromDate: String, through: String) {
        var byWeek: [String: [PlannedDay]] = [:]
        for day in response.plan.days {
            guard let start = weekStart(of: day.date) else { continue }
            byWeek[start, default: []].append(day)
        }
        var updated = weeks
        for (weekStart, days) in byWeek {
            let generated = WeekPlanV2(
                weekStart: weekStart,
                generatedAt: response.generatedAt,
                rationale: response.plan.rationale,
                adjustments: response.adjustments,
                wishes: response.wishes,
                days: days
            )
            let merged = MultiSportWeekEditor.merge(
                existing: updated.first { $0.weekStart == weekStart }, generated: generated, fromDate: fromDate, through: through
            )
            updated = updated.filter { $0.weekStart != weekStart } + [merged]
        }
        save(updated)
    }

    // MARK: - Ändern

    public func markUnavailable(_ date: String) {
        edit(date) { MultiSportWeekEditor.markUnavailable($0, date: date) }
    }

    public func clearUnavailable(_ date: String) {
        edit(date) { MultiSportWeekEditor.clearUnavailable($0, date: date) }
    }

    public func setRest(_ date: String) {
        edit(date) { MultiSportWeekEditor.setRest($0, date: date) }
    }

    public func setAmount(_ date: String, session index: Int, amount: Double) {
        let registry = self.registry
        edit(date) { MultiSportWeekEditor.setAmount($0, date: date, session: index, amount: amount, registry: registry) }
    }

    public func removeSession(_ date: String, session index: Int) {
        edit(date) { MultiSportWeekEditor.removeSession($0, date: date, session: index) }
    }

    public func addSession(_ date: String, sport: SportID) {
        let registry = self.registry
        edit(date) { MultiSportWeekEditor.addSession($0, date: date, sport: sport, registry: registry) }
    }

    public func changeSport(_ date: String, session index: Int, to sport: SportID) {
        let registry = self.registry
        edit(date) { MultiSportWeekEditor.changeSport($0, date: date, session: index, to: sport, registry: registry) }
    }

    /// Zwei Tage derselben Woche tauschen.
    public func swapDays(_ first: String, _ second: String) {
        guard weekStart(of: first) == weekStart(of: second) else { return }
        edit(first) { MultiSportWeekEditor.swap($0, first, second) }
    }

    public func moveToRestDay(from source: String, to target: String) {
        guard weekStart(of: source) == weekStart(of: target) else { return }
        edit(source) { MultiSportWeekEditor.moveToRestDay($0, from: source, to: target) }
    }

    /// Wendet eine Änderung auf die Woche des Tages an und speichert. Ohne Plan für die Woche passiert nichts.
    private func edit(_ date: String, _ change: (WeekPlanV2) -> WeekPlanV2) {
        guard let start = weekStart(of: date), let current = week(starting: start) else { return }
        let changed = change(current)
        guard changed != current else { return }
        save(weeks.filter { $0.weekStart != start } + [changed])
    }

    private func save(_ plans: [WeekPlanV2]) {
        var sorted = plans.sorted { $0.weekStart < $1.weekStart }
        if sorted.count > Self.retainedWeeks {
            sorted.removeFirst(sorted.count - Self.retainedWeeks)
        }
        weeks = sorted
        // Speichern ist Komfort; scheitert es, ist der Plan im Speicher trotzdem da.
        try? store.save(sorted)
    }

    private func weekStart(of date: String) -> String? {
        weekCalendar.date(from: date).map { weekCalendar.weekStart(containing: $0) }
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
