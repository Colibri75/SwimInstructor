import Foundation

/// Wie ein Tag der Woche im Vergleich zum Plan steht.
public enum WeekDayState: Equatable, Sendable {
    /// Kein Eintrag im Wochenplan (z. B. Tage vor dem Planen).
    case unplanned
    /// Geplant, noch nicht dran.
    case upcoming
    /// Heute, noch offen.
    case today
    /// Training geplant und ungefähr der geplante Umfang geschwommen (75 bis 125 %).
    case followed
    case shorter
    case longer
    /// Training geplant, nicht geschwommen.
    case missed
    case restKept
    /// Ruhetag geplant, trotzdem geschwommen.
    case restBroken
    /// Der Athlet hat an diesem Tag keine Zeit.
    case skipped
}

public struct WeekDayStatus: Identifiable, Equatable, Sendable {
    /// Kalendertag `yyyy-MM-dd`.
    public let date: String
    public let plan: WeekDayPlan?
    public let actualMeters: Double
    public let workoutCount: Int
    public let state: WeekDayState

    public var id: String { date }

    public init(date: String, plan: WeekDayPlan?, actualMeters: Double, workoutCount: Int, state: WeekDayState) {
        self.date = date
        self.plan = plan
        self.actualMeters = actualMeters
        self.workoutCount = workoutCount
        self.state = state
    }
}

/// Die Zahlen oben im Wochen-Tab und in der Statistik von "Heute".
public struct WeekSummary: Equatable, Sendable {
    /// Geplante Meter der ganzen Woche (ohne Tage ohne Zeit).
    public let plannedMeters: Int
    /// In der Woche geschwommene Meter, auch an ungeplanten Tagen.
    public let swumMeters: Int
    /// Geplante Trainingstage, die schon vorbei sind oder heute erledigt wurden.
    public let sessionsDue: Int
    /// Davon geschwommen (egal wie viel).
    public let sessionsDone: Int
    /// Geplante Trainingstage der ganzen Woche.
    public let sessionsPlanned: Int

    public init(plannedMeters: Int, swumMeters: Int, sessionsDue: Int, sessionsDone: Int, sessionsPlanned: Int) {
        self.plannedMeters = plannedMeters
        self.swumMeters = swumMeters
        self.sessionsDue = sessionsDue
        self.sessionsDone = sessionsDone
        self.sessionsPlanned = sessionsPlanned
    }
}

/// Legt den Wochenplan neben die tatsächlich geschwommenen Einheiten.
public struct WeekProgressCalculator: Sendable {
    public static let lowerTolerance = 0.75
    public static let upperTolerance = 1.25

    private let weekCalendar: WeekCalendar
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.weekCalendar = WeekCalendar(calendar: calendar)
    }

    /// Ein Eintrag je Tag der Woche (Montag bis Sonntag), auch ohne Plan.
    public func statuses(plan: WeekPlan?, weekStart: String, workouts: [SwimWorkout], now: Date) -> [WeekDayStatus] {
        let todayKey = PlanFormatting.isoDay(now, calendar: calendar)
        var meters: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for workout in workouts where workout.startDate <= now {
            let key = PlanFormatting.isoDay(workout.startDate, calendar: calendar)
            meters[key, default: 0] += workout.totalDistanceMeters ?? 0
            counts[key, default: 0] += 1
        }

        return weekCalendar.dates(inWeekStarting: weekStart).map { date in
            let day = plan?.day(on: date)
            let actual = meters[date] ?? 0
            let count = counts[date] ?? 0
            return WeekDayStatus(
                date: date,
                plan: day,
                actualMeters: actual,
                workoutCount: count,
                state: state(for: day, date: date, today: todayKey, meters: actual, count: count)
            )
        }
    }

    public func summary(of statuses: [WeekDayStatus]) -> WeekSummary {
        var planned = 0, swum = 0, due = 0, done = 0, sessions = 0
        for status in statuses {
            swum += Int(status.actualMeters.rounded())
            guard let day = status.plan, !day.isUnavailable else { continue }
            planned += day.targetDistanceMeters
            guard !day.isRestDay else { continue }
            sessions += 1
            switch status.state {
            case .followed, .shorter, .longer:
                due += 1
                done += 1
            case .missed:
                due += 1
            default:
                break
            }
        }
        return WeekSummary(plannedMeters: planned, swumMeters: swum, sessionsDue: due, sessionsDone: done, sessionsPlanned: sessions)
    }

    private func state(for day: WeekDayPlan?, date: String, today: String, meters: Double, count: Int) -> WeekDayState {
        guard let day else { return .unplanned }
        if day.isUnavailable { return .skipped }
        let isToday = date == today
        if date > today { return .upcoming }

        let swamAnything = count > 0
        if day.isRestDay {
            if swamAnything { return .restBroken }
            return isToday ? .today : .restKept
        }
        guard swamAnything else { return isToday ? .today : .missed }

        // Eine Einheit ohne Streckenangabe lässt sich nicht vergleichen und zählt als umgesetzt.
        let planned = Double(day.targetDistanceMeters)
        guard planned > 0, meters > 0 else { return .followed }
        let ratio = meters / planned
        // Heute kann noch eine zweite Einheit folgen: Erst am Tagesende zählt "zu kurz".
        if ratio < Self.lowerTolerance { return isToday ? .today : .shorter }
        if ratio > Self.upperTolerance { return .longer }
        return .followed
    }
}
