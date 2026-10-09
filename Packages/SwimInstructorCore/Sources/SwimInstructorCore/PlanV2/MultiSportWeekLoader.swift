import Foundation

/// Steuert die nächsten 14 Tage in Plan v2: vom Server holen, Änderungen des Athleten anwenden, alles auf dem Gerät
/// speichern. Null bis zwei Einheiten je Tag über alle Sportarten. Absichtlich ohne SwiftUI.
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
    public static let windowDays = 14
    /// So viele Tage vor heute gehen als bisheriges Training mit (die Grenzen gelten für jede Spanne von 7 Tagen).
    public static let historyDays = 7

    @Published public private(set) var weeks: [WeekPlanV2]
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    /// Kein Token hinterlegt.
    @Published public private(set) var needsConfiguration = false
    /// Die Woche, die der Plan-Tab zeigt (Montag, `yyyy-MM-dd`).
    @Published public var selectedWeekStart: String
    /// Warum die nächsten Tage zuletzt außer der Reihe neu geplant wurden (Beschwerden, sehr harte Einheit, Ausfall);
    /// `nil`, wenn es die tägliche Abstimmung war.
    @Published public private(set) var lastAdaptation: AdaptationSignal?

    /// Liefert Zustand und Einheiten; wird nach dem Anlegen gesetzt, weil es vom Heute-Bildschirm abhängt.
    public var contextProvider: @MainActor () -> PlanningContext? = { nil }
    /// Das Equipment des Athleten (Rohwerte); `nil`: keine Angabe.
    public var equipmentProvider: @MainActor () -> [String]? = { nil }
    /// Was der Gesamtplan für die Wochen der Tage vorgibt.
    public var macroProvider: @MainActor ([String]) -> [MacroWeekV2] = { _ in [] }
    public var testSettingsProvider: @MainActor () -> TestSettings? = { nil }
    /// Die letzte Woche des Gesamtplans (Montag); bis dorthin lässt sich im Plan-Tab vorblättern. `nil` ohne Gesamtplan.
    public var lastWeekStartProvider: @MainActor () -> String? = { nil }
    /// Die Rückmeldungen des Athleten zu seinen Einheiten (Anstrengung, Beschwerden).
    public var feedbackProvider: @MainActor () -> [SessionFeedback] = { [] }
    /// Kraft und Mobilität, Ort und freie Zeit für die angefragten Tage.
    public var extrasProvider: @MainActor ([String]) -> PlanningExtras = { _ in .none }
    /// Nach jeder Änderung von Hand im Plan-Tab: Heute und die Watch ziehen nach, wenn heute betroffen ist.
    public var onEdit: @MainActor () -> Void = {}
    /// Ob heute feststeht (es gibt schon einen Tagesplan oder eine Vorschau, oder es wurde schon trainiert): Dann bleibt
    /// heute beim Neu-Abstimmen, wie es ist.
    public var todayLockedProvider: @MainActor () -> Bool = { false }

    private let store: WeekPlanV2Storing
    private let dailyMarker: DailyRefreshMarking
    private let adaptationMarker: AdaptationMarking
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
        adaptationMarker: AdaptationMarking = UserDefaultsAdaptationMarker(),
        registry: SportRegistry = .standard,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.store = store
        self.dailyMarker = dailyMarker
        self.adaptationMarker = adaptationMarker
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

    /// Der letzte Tag, den der rollende Plan abdeckt (heute und 13 weitere Tage).
    public var windowEnd: String { weekCalendar.addingDays(Self.windowDays - 1, to: todayKey) ?? todayKey }

    /// Ob `date` nach den geplanten 14 Tagen liegt: Für diese Tage gibt es noch keine Einheiten, nur die Vorgabe des
    /// Gesamtplans für die Woche und den Wochenraster.
    public func isBeyondWindow(_ date: String) -> Bool { date > windowEnd }

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
            feedback: feedbackProvider(),
            registry: registry,
            calendar: calendar
        )
    }

    /// Das Training der sieben Tage vor heute und von heute, für den Tagesplan.
    public func recentTrainingForToday(snapshot: AthleteStateSnapshot, workouts: [Workout]) -> [RecentTrainingEntry] {
        let start = weekCalendar.addingDays(-Self.historyDays, to: todayKey) ?? todayKey
        let end = weekCalendar.addingDays(1, to: todayKey) ?? todayKey
        return recentTraining(from: start, before: end, snapshot: snapshot, workouts: workouts)
    }

    // MARK: - Planen

    /// Geplante Einheiten der letzten Tage, die ausgefallen sind.
    public func missedSessions(workouts: [Workout]) -> [MissedSession] {
        Adaptation.missedSessions(weeks: weeks, workouts: workouts.filter { $0.startDate <= now() }, today: todayKey, calendar: calendar)
    }

    /// Ein neuer Anlass, die Tage sofort neu abzustimmen (Beschwerden, sehr harte Einheit, Ausfall gestern), sonst `nil`.
    public func pendingAdaptation() -> AdaptationSignal? {
        guard let context = contextProvider() else { return nil }
        let workouts = context.workouts.filter { $0.startDate <= now() }
        return Adaptation.signal(
            feedback: feedbackProvider(),
            missed: missedSessions(workouts: workouts),
            workouts: workouts,
            today: todayKey,
            handled: adaptationMarker.handled(),
            calendar: calendar
        )
    }

    /// Plant die nächsten 14 Tage ab heute neu, abgestimmt auf Zustand, bisheriges Training und Gesamtplan. Tage ohne
    /// Zeit bleiben Ruhetage. Liefert `true`, wenn der Plan erneuert wurde.
    @discardableResult
    public func planNextDays(wishes: String? = nil, reason: ReplanReason = .manual) async -> Bool {
        guard !isLoading else { return false }
        guard let context = contextProvider() else {
            error = String(localized: "Die Health-Daten sind noch nicht geladen. Öffne zuerst den Tab Aktuell.")
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
        let fixed = fixedDates(in: dates)
        let request = WeekPlanV2Request(
            snapshot: context.snapshot,
            fromDate: fromDate,
            today: fromDate,
            days: Self.windowDays,
            unavailableDates: unavailable.sorted(),
            fixedDays: fixed.compactMap { date in day(on: date).map { FixedDayV2(date: date, target: $0.target) } },
            // Mit heute: Beschwerden nach einer Einheit von heute bremsen schon die nächsten Tage (der Server zählt
            // heutige Einheiten nur dafür, nicht für die Grenzen davor).
            recentTraining: recentTraining(
                from: weekCalendar.addingDays(-Self.historyDays, to: fromDate) ?? fromDate,
                before: weekCalendar.addingDays(1, to: fromDate) ?? fromDate,
                snapshot: context.snapshot,
                workouts: context.workouts
            ),
            macroWeeks: macroProvider(dates),
            wishes: wishes,
            equipment: equipmentProvider(),
            testSettings: testSettingsProvider(),
            missedSessions: missedSessions(workouts: context.workouts),
            reason: reason,
            extras: extrasProvider(dates)
        )

        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await provider.fetchWeekPlanV2(request)
            apply(response, fromDate: fromDate, through: through, keep: Set(fixed))
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Einmal am Tag, beim ersten Öffnen: die nächsten 14 Tage neu abstimmen. Schlägt es fehl, gilt der Tag nicht als
    /// erledigt. Ändert sich `stamp` (etwa mit dem Ziel oder dem Gesamtplan), gilt der Tag wieder als offen.
    ///
    /// Außer der Reihe, auch mehrmals am Tag: Hat der Athlet Beschwerden gemeldet, war eine Einheit sehr hart oder ist
    /// gestern eine geplante Einheit ausgefallen, plant die App sofort neu (jeder Anlass einmal).
    public func refreshDaily(wishes: String? = nil, stamp: String = "") async {
        let marker = "\(todayKey)|\(stamp)"
        let signal = pendingAdaptation()
        guard dailyMarker.lastDay() != marker || signal != nil else { return }
        if await planNextDays(wishes: wishes, reason: signal?.reason ?? .daily) {
            dailyMarker.setLastDay(marker)
            if let signal {
                adaptationMarker.markHandled(signal.key)
                lastAdaptation = signal
            }
        }
    }

    /// Verteilt die Tage der Antwort auf ihre Kalenderwochen und führt sie mit den gespeicherten zusammen.
    /// Tage, die beim Neu-Abstimmen bleiben: von Hand geänderte und heute, wenn es feststeht. Tage ohne Zeit gehen
    /// getrennt mit.
    public func fixedDates(in dates: [String]) -> [String] {
        let today = todayKey
        let todayLocked = todayLockedProvider()
        return dates.filter { date in
            guard let day = day(on: date), !day.isUnavailable else { return false }
            return day.isEdited || (date == today && todayLocked)
        }
    }

    private func apply(_ response: WeekPlanV2Response, fromDate: String, through: String, keep: Set<String> = []) {
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
                existing: updated.first { $0.weekStart == weekStart }, generated: generated, fromDate: fromDate, through: through, keep: keep
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

    /// Gibt einen von Hand geänderten Tag an den Coach zurück (beim nächsten Abstimmen plant er ihn wieder).
    public func release(_ date: String) {
        edit(date) { MultiSportWeekEditor.release($0, date: date) }
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
        onEdit()
    }

    // MARK: - Tagesplan übernehmen

    /// Übernimmt den Tagesplan von heute in die Woche (Sportart, Art, Umfang, Test, Koppeltraining, drinnen, Freiwasser,
    /// Kraft und Mobilität). So zeigen Plan-Tab, Heute und Watch dasselbe, auch wenn der Tagesplan nach einem Wunsch
    /// anders ausfällt als die Vorgabe. Ein Plan von einem anderen Tag oder ein Ersatzplan ändert nichts; ein Tag ohne Zeit
    /// bleibt ohne Zeit. Liefert die Vorgabe für heute danach.
    @discardableResult
    public func adoptTodayPlan(_ response: DayPlanV2Response) -> DayTargetV2? {
        let today = todayKey
        guard response.date == today, response.source != .fallback,
              let start = weekStart(of: today), let current = week(starting: start),
              let index = current.days.firstIndex(where: { $0.date == today }), !current.days[index].isUnavailable else {
            return todayTarget
        }
        let sessions = response.plan.sessions.map { session in
            WeekSession(
                sport: session.sport, sessionType: session.sessionType, intensity: session.intensity,
                amount: session.amount, unit: session.unit, minutes: session.durationMinutes,
                distanceMeters: session.distanceMeters, focus: session.focus, test: session.test,
                brick: session.brick, indoor: session.indoor, openWater: session.openWater
            )
        }
        let extras = response.plan.extras.map { WeekExtra(kind: $0.kind, minutes: $0.minutes, focus: $0.focus) }
        var changed = current
        var day = changed.days[index]
        guard day.sessions != sessions || day.extras != extras else { return todayTarget }
        if sessions.isEmpty != day.sessions.isEmpty {
            day.focus = sessions.isEmpty ? String(localized: "Ruhetag") : sessions.map(\.focus).joined(separator: " + ")
        }
        day.sessions = sessions
        day.extras = extras
        changed.days[index] = day
        save(weeks.filter { $0.weekStart != start } + [changed])
        return todayTarget
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

    /// So weit zurück lässt sich blättern: vier Wochen.
    public var earliestWeekStart: String { weekCalendar.addingDays(-28, to: currentWeekStart) ?? currentWeekStart }

    /// So weit voraus lässt sich blättern: bis zur letzten Woche des Gesamtplans, mindestens bis zur Woche mit dem letzten
    /// geplanten Tag.
    public var latestWeekStart: String {
        let nextWeek = weekCalendar.addingDays(7, to: currentWeekStart) ?? currentWeekStart
        let planned = max(nextWeek, weekStart(of: windowEnd) ?? nextWeek)
        guard let last = lastWeekStartProvider(), let date = weekCalendar.date(from: last) else { return planned }
        return max(planned, weekCalendar.weekStart(containing: date))
    }

    public func canShiftSelectedWeek(by weeksDelta: Int) -> Bool {
        guard let target = weekCalendar.addingDays(weeksDelta * 7, to: selectedWeekStart) else { return false }
        return target >= earliestWeekStart && target <= latestWeekStart
    }

    /// Eine Woche vor oder zurück, höchstens vier Wochen zurück und bis zum Ende des Gesamtplans voraus.
    public func shiftSelectedWeek(by weeksDelta: Int) {
        guard canShiftSelectedWeek(by: weeksDelta),
              let target = weekCalendar.addingDays(weeksDelta * 7, to: selectedWeekStart) else { return }
        selectedWeekStart = target
    }

    /// Zeigt die Woche, in der `date` liegt, wenn sie im erlaubten Bereich liegt. Liefert `true`, wenn sie gewählt ist.
    @discardableResult
    public func selectWeek(containing date: String) -> Bool {
        guard let start = weekStart(of: date), start >= earliestWeekStart, start <= latestWeekStart else { return false }
        selectedWeekStart = start
        return true
    }
}
