import Foundation

/// Bin ich auf Kurs zum Ziel? Plan gegen Ist der letzten abgeschlossenen Wochen des Gesamtplans, je Sportart und
/// gesamt, mit einer Ampel und einem kurzen Satz. Dazu die Belastung aller Wochen bis zum Ziel (geplant und trainiert)
/// für die Linie in "Weg zum Ziel". Reine Rechnung ohne SwiftUI: Karte in "Aktuell", der Bildschirm dahinter und die
/// Wochenbilanz als Mitteilung lesen dasselbe Ergebnis.
public struct GoalCourse: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        /// Gesamt zwischen 80 und 120 % des Plans, keine Sportart unter 60 %.
        case onTrack = "on_track"
        /// Gesamt unter 80 % oder eine Sportart unter 60 %.
        case trainMore = "train_more"
        /// Gesamt über 120 %: mehr als der Plan, das bringt nicht schneller ans Ziel.
        case trainLess = "train_less"
        /// Noch keine abgeschlossene Woche mit Plan.
        case noData = "no_data"

        public var title: String {
            switch self {
            case .onTrack: return String(localized: "Auf Kurs")
            case .trainMore: return String(localized: "Etwas zu wenig")
            case .trainLess: return String(localized: "Mehr als geplant")
            case .noData: return String(localized: "Noch zu früh")
            }
        }
    }

    /// Eine Sportart über die bewerteten Wochen, in ihrer Planeinheit (Meter oder Minuten).
    public struct SportCourse: Equatable, Sendable, Identifiable {
        public let sport: SportID
        public let unit: PlanUnit
        public let planned: Double
        public let done: Double
        public let plannedSessions: Int
        public let doneSessions: Int

        public var id: SportID { sport }

        public init(sport: SportID, unit: PlanUnit, planned: Double, done: Double, plannedSessions: Int, doneSessions: Int) {
            self.sport = sport
            self.unit = unit
            self.planned = planned
            self.done = done
            self.plannedSessions = plannedSessions
            self.doneSessions = doneSessions
        }

        /// Erfüllung in Prozent, `nil` ohne Plan.
        public var percent: Int? { MacroActualCalculator.percent(planned: planned, actual: done) }
    }

    /// Eine Woche des Gesamtplans für die Linie: geplante und trainierte Minuten.
    public struct WeekPoint: Equatable, Sendable, Identifiable {
        /// Montag, `yyyy-MM-dd`.
        public let weekStart: String
        public let plannedMinutes: Double
        /// Trainierte Minuten; `nil` für Wochen, die noch nicht begonnen haben.
        public let doneMinutes: Double?
        public let isCurrent: Bool

        public var id: String { weekStart }

        public init(weekStart: String, plannedMinutes: Double, doneMinutes: Double?, isCurrent: Bool) {
            self.weekStart = weekStart
            self.plannedMinutes = plannedMinutes
            self.doneMinutes = doneMinutes
            self.isCurrent = isCurrent
        }
    }

    public let status: Status
    /// Gesamt in Prozent des Plans (Sportarten nach geplanten Minuten gewichtet), `nil` ohne bewertete Woche.
    public let percent: Int?
    /// Die bewerteten Wochen (Montage), älteste zuerst.
    public let weekStarts: [String]
    public let sports: [SportCourse]
    /// Alle Wochen des Gesamtplans für die Linie.
    public let weeks: [WeekPoint]

    public init(status: Status, percent: Int?, weekStarts: [String], sports: [SportCourse], weeks: [WeekPoint]) {
        self.status = status
        self.percent = percent
        self.weekStarts = weekStarts
        self.sports = sports
        self.weeks = weeks
    }

    public var plannedSessions: Int { sports.reduce(0) { $0 + $1.plannedSessions } }
    public var doneSessions: Int { sports.reduce(0) { $0 + $1.doneSessions } }

    /// Sportarten unter 80 % des Plans.
    public var lowSports: [SportID] {
        sports.filter { ($0.percent ?? 100) < GoalCourseEvaluator.onTrackPercent }.map(\.sport)
    }

    /// Ein, zwei Sätze zum Stand, ohne Coach (die Karte zeigt den Rat der letzten Fortschreibung, wenn es ihn gibt).
    public func sentence(registry: SportRegistry = .standard) -> String {
        guard let percent, !weekStarts.isEmpty else {
            return String(localized: "Nach der ersten vollen Woche mit Plan siehst du hier, ob du auf Kurs bist.")
        }
        let first = weekStarts.count == 1
            ? String(localized: "Letzte Woche hast du \(percent) % vom Plan trainiert.")
            : String(localized: "In den letzten \(weekStarts.count) Wochen hast du \(percent) % vom Plan trainiert.")
        let names = lowSports.map { registry.displayName(for: $0) }.formatted(.list(type: .and).locale(AppLocale.current))
        let second: String
        switch status {
        case .onTrack:
            second = lowSports.isEmpty
                ? String(localized: "Mach so weiter.")
                : String(localized: "Bei \(names) fehlt etwas, sonst passt es.")
        case .trainMore:
            second = lowSports.isEmpty
                ? String(localized: "Versuch, die geplanten Einheiten zu schaffen.")
                : String(localized: "Versuch, die geplanten Einheiten zu schaffen, vor allem bei \(names).")
        case .trainLess:
            second = String(localized: "Mehr als geplant bringt dich nicht schneller ans Ziel. Halte dich an den Plan und gönn dir die Ruhetage.")
        case .noData:
            second = ""
        }
        return second.isEmpty ? first : "\(first) \(second)"
    }
}

/// Rechnet `GoalCourse` aus dem Gesamtplan und den Einheiten aus Health.
public struct GoalCourseEvaluator: Sendable {
    /// So viele abgeschlossene Wochen zählen.
    public static let lookbackWeeks = 4
    /// Ab so viel Prozent gesamt gilt man als auf Kurs.
    public static let onTrackPercent = 80
    /// Über so viel Prozent gesamt: mehr als geplant.
    public static let tooMuchPercent = 120
    /// Liegt eine Sportart darunter, reicht es insgesamt nicht.
    public static let weakSportPercent = MacroActualCalculator.lowCompliancePercent
    /// Eine Woche mit so vielen Tagen gemeldeter Pause zählt nicht.
    public static let pauseDaysToSkipWeek = 3
    /// Mehr als so viel Prozent zählt je Sportart nicht in die Gesamtzahl (viel Rad gleicht kein fehlendes Laufen aus).
    static let cappedPercent = 150.0

    public let registry: SportRegistry
    public let calendar: Calendar
    private let weekCalendar: WeekCalendar

    public init(registry: SportRegistry = .standard, calendar: Calendar = .current) {
        self.registry = registry
        self.calendar = calendar
        self.weekCalendar = WeekCalendar(calendar: calendar)
    }

    /// Bewertet die letzten `lookbackWeeks` abgeschlossenen Wochen. Die Woche, in der der Plan entstand, zählt nicht
    /// (sie war nur zum Teil geplant), ebenso Wochen mit gemeldeter Pause. `historyStart`: ab hier liegen Einheiten vor
    /// (die App liest `SnapshotBuilder.workoutWindowDays` Tage); ältere Wochen zeigen in der Linie kein Ist statt 0.
    public func evaluate(plan: MacroPlanV2, workouts: [Workout], now: Date, pause: PauseReport? = nil, historyStart: Date? = nil) -> GoalCourse {
        let currentWeekStart = weekCalendar.weekStart(containing: now)
        let firstWeekStart = weekCalendar.weekStart(containing: plan.generatedAt)
        let deduplicated = WorkoutDeduplicator.deduplicate(workouts)
        let byWeek = Dictionary(grouping: deduplicated) { weekCalendar.weekStart(containing: $0.startDate) }
        // Die erste Woche, die ganz in den gelesenen Einheiten liegt.
        let firstKnownWeekStart = historyStart.map { start -> String in
            let week = weekCalendar.weekStart(containing: start)
            return week == weekCalendar.key(for: calendar.startOfDay(for: start)) ? week : (weekCalendar.addingDays(7, to: week) ?? week)
        }

        let evaluated = plan.weeks
            .filter { $0.weekStart < currentWeekStart && $0.weekStart > firstWeekStart && $0.totalMinutes > 0 }
            .filter { !isPaused($0.weekStart, pause: pause) && $0.weekStart >= (firstKnownWeekStart ?? "") }
            .suffix(Self.lookbackWeeks)

        let points = plan.weeks.map { week -> GoalCourse.WeekPoint in
            let started = week.weekStart <= currentWeekStart && week.weekStart >= (firstKnownWeekStart ?? "")
            let minutes = (byWeek[week.weekStart] ?? []).reduce(0.0) { $0 + $1.duration / 60 }
            return GoalCourse.WeekPoint(
                weekStart: week.weekStart,
                plannedMinutes: week.totalMinutes,
                doneMinutes: started ? minutes.rounded() : nil,
                isCurrent: week.weekStart == currentWeekStart
            )
        }

        guard !evaluated.isEmpty else {
            return GoalCourse(status: .noData, percent: nil, weekStarts: [], sports: [], weeks: points)
        }

        var weights: [SportID: Double] = [:]
        let sports = plan.sports.compactMap { sport -> GoalCourse.SportCourse? in
            let unit = registry.module(for: sport)?.planUnit ?? .minutes
            var planned = 0.0, done = 0.0, plannedSessions = 0, doneSessions = 0, plannedMinutes = 0.0
            for week in evaluated {
                guard let volume = week.volume(of: sport) else { continue }
                planned += volume.amount
                plannedSessions += volume.sessions
                plannedMinutes += volume.minutes
                let sessions = (byWeek[week.weekStart] ?? []).filter { $0.sport == sport }
                doneSessions += sessions.count
                done += sessions.reduce(0.0) { total, workout in
                    total + (unit == .meters ? (workout.distanceMeters ?? 0) : workout.duration / 60)
                }
            }
            guard planned > 0 else { return nil }
            weights[sport] = max(plannedMinutes, 1)
            return GoalCourse.SportCourse(
                sport: sport, unit: unit, planned: planned.rounded(), done: done.rounded(),
                plannedSessions: plannedSessions, doneSessions: doneSessions
            )
        }

        let totalWeight = sports.reduce(0.0) { $0 + (weights[$1.sport] ?? 0) }
        guard totalWeight > 0 else {
            return GoalCourse(status: .noData, percent: nil, weekStarts: [], sports: [], weeks: points)
        }
        let weighted = sports.reduce(0.0) { total, course in
            let share = min(course.done / course.planned * 100, Self.cappedPercent)
            return total + share * (weights[course.sport] ?? 0)
        }
        let percent = Int((weighted / totalWeight).rounded())
        let hasWeakSport = sports.contains { ($0.percent ?? 100) < Self.weakSportPercent }

        let status: GoalCourse.Status
        if percent < Self.onTrackPercent || hasWeakSport {
            status = .trainMore
        } else if percent > Self.tooMuchPercent {
            status = .trainLess
        } else {
            status = .onTrack
        }
        return GoalCourse(status: status, percent: percent, weekStarts: evaluated.map(\.weekStart), sports: sports, weeks: points)
    }

    /// Liegen in der Woche ab `weekStart` mindestens `pauseDaysToSkipWeek` Tage der gemeldeten Pause?
    private func isPaused(_ weekStart: String, pause: PauseReport?) -> Bool {
        guard let pause, pause.problem == nil else { return false }
        let days = weekCalendar.dates(inWeekStarting: weekStart).filter { pause.contains($0) }
        return days.count >= Self.pauseDaysToSkipWeek
    }
}
