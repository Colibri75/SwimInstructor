import Foundation

/// Was eine Sportart an einem Tag vorsah und was der Athlet gemacht hat, in der Einheit der Sportart (Meter oder
/// Minuten).
public struct SportComparison: Identifiable, Equatable, Sendable {
    public let sport: SportID
    public let unit: PlanUnit
    public let planned: Double
    public let actual: Double
    public let plannedSessions: Int
    public let workoutCount: Int
    /// Geplante Minuten (für den Vergleich über alle Sportarten).
    public let plannedMinutes: Double
    /// Tatsächliche Minuten.
    public let actualMinutes: Double

    public var id: SportID { sport }
    public var isPlanned: Bool { plannedSessions > 0 }

    public init(
        sport: SportID,
        unit: PlanUnit,
        planned: Double,
        actual: Double,
        plannedSessions: Int,
        workoutCount: Int,
        plannedMinutes: Double,
        actualMinutes: Double
    ) {
        self.sport = sport
        self.unit = unit
        self.planned = planned
        self.actual = actual
        self.plannedSessions = plannedSessions
        self.workoutCount = workoutCount
        self.plannedMinutes = plannedMinutes
        self.actualMinutes = actualMinutes
    }
}

/// Plan gegen Ist für alle Sportarten: je Sportart in ihrer Einheit, für den Tag über alle Sportarten.
public struct MultiSportComparator: Sendable {
    /// Ab 75 % bis 125 % des geplanten Umfangs gilt ein Tag als umgesetzt.
    public static let lowerTolerance = 0.75
    public static let upperTolerance = 1.25

    private let registry: SportRegistry

    public init(registry: SportRegistry = .standard) {
        self.registry = registry
    }

    /// Ein geplanter Umfang: Sportart, Menge in ihrer Einheit, Minuten.
    public struct Planned: Equatable, Sendable {
        public let sport: SportID
        public let unit: PlanUnit
        public let amount: Double
        public let minutes: Double

        public init(sport: SportID, unit: PlanUnit, amount: Double, minutes: Double) {
            self.sport = sport
            self.unit = unit
            self.amount = amount
            self.minutes = minutes
        }
    }

    /// Je Sportart, die geplant war oder gemacht wurde, ein Vergleich: geplante zuerst in der Reihenfolge des Plans,
    /// dann die übrigen in der Reihenfolge der Registry. Einheiten unbekannter Sportarten zählen nicht.
    public func compare(planned: [Planned], workouts: [Workout]) -> [SportComparison] {
        let known = workouts.filter { registry.module(for: $0.sport) != nil }
        var order: [SportID] = []
        for entry in planned where !order.contains(entry.sport) {
            order.append(entry.sport)
        }
        for module in registry.modules where !order.contains(module.id) && known.contains(where: { $0.sport == module.id }) {
            order.append(module.id)
        }
        return order.map { sport in
            let plans = planned.filter { $0.sport == sport }
            let done = known.filter { $0.sport == sport }
            let unit = plans.first?.unit ?? registry.module(for: sport)?.planUnit ?? .minutes
            let speed = registry.module(for: sport)?.typicalSpeedMetersPerSecond ?? 2
            let actual: Double
            switch unit {
            case .meters:
                // Ohne Strecke in Health schätzt die Dauer die Meter.
                actual = done.reduce(0) { $0 + ($1.distanceMeters ?? $1.duration * speed) }
            case .minutes:
                actual = done.reduce(0) { $0 + $1.duration / 60 }
            }
            return SportComparison(
                sport: sport,
                unit: unit,
                planned: plans.reduce(0) { $0 + $1.amount },
                actual: actual,
                plannedSessions: plans.count,
                workoutCount: done.count,
                plannedMinutes: plans.reduce(0) { $0 + $1.minutes },
                actualMinutes: done.reduce(0) { $0 + $1.duration / 60 }
            )
        }
    }

    /// Wie der Tag ausging. Geplante Sportarten zählen mit ihrem Anteil am Plan (in ihrer Einheit), gewichtet mit
    /// ihren geplanten Minuten; eine andere Sportart statt der geplanten zählt mit ihren Minuten.
    public func outcome(of comparisons: [SportComparison], isRestDay: Bool, isToday: Bool) -> AdherenceOutcome {
        let didAnything = comparisons.contains { $0.workoutCount > 0 }
        if isRestDay {
            if didAnything { return .restBroken }
            return isToday ? .pending : .restKept
        }
        guard didAnything else { return isToday ? .pending : .missed }

        let plannedMinutes = comparisons.reduce(0) { $0 + $1.plannedMinutes }
        guard plannedMinutes > 0 else { return .followed }
        let equivalent = comparisons.reduce(0.0) { sum, comparison in
            if comparison.isPlanned {
                guard comparison.planned > 0 else { return sum + comparison.actualMinutes }
                return sum + comparison.actual / comparison.planned * comparison.plannedMinutes
            }
            return sum + comparison.actualMinutes
        }
        let ratio = equivalent / plannedMinutes
        // Heute kann noch eine Einheit folgen: Erst am Tagesende zählt "zu kurz".
        if ratio < Self.lowerTolerance { return isToday ? .pending : .shorter }
        if ratio > Self.upperTolerance { return .longer }
        return .followed
    }
}

// MARK: - Verlauf (Tagespläne)

/// Ein gespeicherter Tagesplan neben dem, was der Athlet an dem Tag gemacht hat.
public struct MultiSportAdherenceEntry: Identifiable, Equatable, Sendable {
    public let date: String
    public let plan: DayPlanV2
    public let comparisons: [SportComparison]
    public let outcome: AdherenceOutcome

    public var id: String { date }

    public init(date: String, plan: DayPlanV2, comparisons: [SportComparison], outcome: AdherenceOutcome) {
        self.date = date
        self.plan = plan
        self.comparisons = comparisons
        self.outcome = outcome
    }
}

/// Legt die gespeicherten Tagespläne v2 neben die Einheiten aller Sportarten.
public struct MultiSportAdherenceCalculator: Sendable {
    private let calendar: Calendar
    private let comparator: MultiSportComparator

    public init(calendar: Calendar = .current, registry: SportRegistry = .standard) {
        self.calendar = calendar
        self.comparator = MultiSportComparator(registry: registry)
    }

    /// Ein Eintrag je Plan der letzten `days` Tage, neuester zuerst. Tage ohne gespeicherten Plan fehlen.
    public func entries(plans: [DayPlanV2Response], workouts: [Workout], days: Int = 28, now: Date) -> [MultiSportAdherenceEntry] {
        let todayKey = PlanFormatting.isoDay(now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        guard let oldest = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let oldestKey = PlanFormatting.isoDay(oldest, calendar: calendar)
        let byDay = Dictionary(grouping: workouts.filter { $0.startDate <= now }) { PlanFormatting.isoDay($0.startDate, calendar: calendar) }

        return plans
            .filter { $0.date >= oldestKey && $0.date <= todayKey }
            .map { response in
                let planned = response.plan.sessions.map {
                    MultiSportComparator.Planned(sport: $0.sport, unit: $0.unit, amount: $0.amount, minutes: $0.durationMinutes)
                }
                let comparisons = comparator.compare(planned: planned, workouts: byDay[response.date] ?? [])
                return MultiSportAdherenceEntry(
                    date: response.date,
                    plan: response.plan,
                    comparisons: comparisons,
                    outcome: comparator.outcome(of: comparisons, isRestDay: response.plan.isRestDay, isToday: response.date == todayKey)
                )
            }
            .sorted { $0.date > $1.date }
    }

    public func summary(of entries: [MultiSportAdherenceEntry]) -> PlanAdherenceSummary {
        PlanAdherenceCalculator.summary(of: entries.map(\.outcome))
    }
}

// MARK: - Woche (Plan der nächsten sieben Tage)

/// Ein Tag der Woche im Plan v2 neben dem, was der Athlet gemacht hat.
public struct MultiSportDayStatus: Identifiable, Equatable, Sendable {
    public let date: String
    public let day: PlannedDay?
    public let comparisons: [SportComparison]
    public let state: WeekDayState

    public var id: String { date }

    public init(date: String, day: PlannedDay?, comparisons: [SportComparison], state: WeekDayState) {
        self.date = date
        self.day = day
        self.comparisons = comparisons
        self.state = state
    }

    public var workoutCount: Int { comparisons.reduce(0) { $0 + $1.workoutCount } }
}

/// Geplant und gemacht in einer Woche für eine Sportart.
public struct SportWeekTotal: Identifiable, Equatable, Sendable {
    public let sport: SportID
    public let unit: PlanUnit
    public let planned: Double
    public let actual: Double
    public let plannedSessions: Int
    public let workoutCount: Int

    public var id: SportID { sport }

    public init(sport: SportID, unit: PlanUnit, planned: Double, actual: Double, plannedSessions: Int, workoutCount: Int) {
        self.sport = sport
        self.unit = unit
        self.planned = planned
        self.actual = actual
        self.plannedSessions = plannedSessions
        self.workoutCount = workoutCount
    }
}

/// Die Zahlen oben im Plan-Tab und in der Statistik: Minuten und Einheiten über alle Sportarten, dazu je Sportart.
public struct MultiSportWeekSummary: Equatable, Sendable {
    /// Geplante Minuten der Woche (ohne Tage ohne Zeit).
    public let plannedMinutes: Double
    /// Trainierte Minuten der Woche, auch an ungeplanten Tagen.
    public let actualMinutes: Double
    /// Geplante Einheiten an Tagen, die vorbei oder heute erledigt sind.
    public let sessionsDue: Int
    /// Davon gemacht (eine Einheit derselben Sportart am selben Tag).
    public let sessionsDone: Int
    /// Geplante Einheiten der ganzen Woche.
    public let sessionsPlanned: Int
    public let sports: [SportWeekTotal]

    public init(plannedMinutes: Double, actualMinutes: Double, sessionsDue: Int, sessionsDone: Int, sessionsPlanned: Int, sports: [SportWeekTotal]) {
        self.plannedMinutes = plannedMinutes
        self.actualMinutes = actualMinutes
        self.sessionsDue = sessionsDue
        self.sessionsDone = sessionsDone
        self.sessionsPlanned = sessionsPlanned
        self.sports = sports
    }
}

/// Legt den Plan v2 einer Woche neben die Einheiten aller Sportarten.
public struct MultiSportWeekProgressCalculator: Sendable {
    private let weekCalendar: WeekCalendar
    private let calendar: Calendar
    private let registry: SportRegistry
    private let comparator: MultiSportComparator

    public init(calendar: Calendar = .current, registry: SportRegistry = .standard) {
        self.calendar = calendar
        self.weekCalendar = WeekCalendar(calendar: calendar)
        self.registry = registry
        self.comparator = MultiSportComparator(registry: registry)
    }

    /// Ein Eintrag je Tag der Woche (Montag bis Sonntag), auch ohne Plan.
    public func statuses(plan: WeekPlanV2?, weekStart: String, workouts: [Workout], now: Date) -> [MultiSportDayStatus] {
        let todayKey = PlanFormatting.isoDay(now, calendar: calendar)
        let byDay = Dictionary(grouping: workouts.filter { $0.startDate <= now }) { PlanFormatting.isoDay($0.startDate, calendar: calendar) }

        return weekCalendar.dates(inWeekStarting: weekStart).map { date in
            let day = plan?.day(on: date)
            let sessions = day.map { $0.isUnavailable ? [] : $0.sessions } ?? []
            let planned = sessions.map { MultiSportComparator.Planned(sport: $0.sport, unit: $0.unit, amount: $0.amount, minutes: $0.minutes) }
            let comparisons = comparator.compare(planned: planned, workouts: byDay[date] ?? [])
            return MultiSportDayStatus(date: date, day: day, comparisons: comparisons, state: state(for: day, date: date, today: todayKey, comparisons: comparisons))
        }
    }

    public func summary(of statuses: [MultiSportDayStatus]) -> MultiSportWeekSummary {
        var plannedMinutes = 0.0, actualMinutes = 0.0, due = 0, done = 0, planned = 0
        var totals: [SportID: SportWeekTotal] = [:]
        var order: [SportID] = []
        for status in statuses {
            for comparison in status.comparisons {
                actualMinutes += comparison.actualMinutes
                if !order.contains(comparison.sport) { order.append(comparison.sport) }
                let previous = totals[comparison.sport]
                totals[comparison.sport] = SportWeekTotal(
                    sport: comparison.sport,
                    unit: previous?.unit ?? comparison.unit,
                    planned: (previous?.planned ?? 0) + comparison.planned,
                    actual: (previous?.actual ?? 0) + comparison.actual,
                    plannedSessions: (previous?.plannedSessions ?? 0) + comparison.plannedSessions,
                    workoutCount: (previous?.workoutCount ?? 0) + comparison.workoutCount
                )
            }
            let sessions = status.comparisons.reduce(0) { $0 + $1.plannedSessions }
            plannedMinutes += status.comparisons.reduce(0) { $0 + $1.plannedMinutes }
            planned += sessions
            switch status.state {
            case .followed, .shorter, .longer, .missed:
                due += sessions
                done += status.comparisons.reduce(0) { $0 + min($1.plannedSessions, $1.workoutCount) }
            default:
                break
            }
        }
        let sports = registry.modules.map(\.id).filter { order.contains($0) } + order.filter { registry.module(for: $0) == nil }
        return MultiSportWeekSummary(
            plannedMinutes: plannedMinutes,
            actualMinutes: actualMinutes,
            sessionsDue: due,
            sessionsDone: done,
            sessionsPlanned: planned,
            sports: sports.compactMap { totals[$0] }
        )
    }

    private func state(for day: PlannedDay?, date: String, today: String, comparisons: [SportComparison]) -> WeekDayState {
        guard let day else { return .unplanned }
        if day.isUnavailable { return .skipped }
        if date > today { return .upcoming }
        switch comparator.outcome(of: comparisons, isRestDay: day.isRestDay, isToday: date == today) {
        case .followed: return .followed
        case .shorter: return .shorter
        case .longer: return .longer
        case .missed: return .missed
        case .restKept: return .restKept
        case .restBroken: return .restBroken
        case .pending: return .today
        }
    }
}
