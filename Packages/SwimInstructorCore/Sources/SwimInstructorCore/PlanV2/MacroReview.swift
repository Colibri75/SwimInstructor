import Foundation

/// Warum der Gesamtplan fortgeschrieben wird (P4). Der Raw-Wert geht als `reason` zum Server.
public enum MacroReviewReason: String, Codable, Sendable, CaseIterable {
    /// Alle zwei Wochen am Montag.
    case scheduled
    /// Der Athlet hat eine Pause von mindestens 7 Tagen gemeldet.
    case pause
    /// Zwei Wochen nacheinander unter 60 % des Plans; der Athlet hat bestätigt.
    case lowCompliance = "low_compliance"

    public var title: String {
        switch self {
        case .scheduled: return "Regelmäßige Fortschreibung"
        case .pause: return "Nach gemeldeter Pause"
        case .lowCompliance: return "Nach zwei schwachen Wochen"
        }
    }
}

/// Eine Fortschreibung des Gesamtplans: Bilanz, Änderungen und Anlass.
public struct MacroReview: Codable, Equatable, Sendable {
    public let reviewedAt: Date
    /// Montag der Woche, in der fortgeschrieben wurde; die nächste regelmäßige folgt zwei Wochen später.
    public let weekStart: String
    public let reason: MacroReviewReason
    public let summary: String
    public let changes: [String]
    public let adjustments: [String]
    public let feedback: String?

    public init(reviewedAt: Date, weekStart: String, reason: MacroReviewReason, summary: String, changes: [String], adjustments: [String] = [], feedback: String? = nil) {
        self.reviewedAt = reviewedAt
        self.weekStart = weekStart
        self.reason = reason
        self.summary = summary
        self.changes = changes
        self.adjustments = adjustments
        self.feedback = feedback
    }
}

/// Was in einer Woche tatsächlich trainiert wurde, je Sportart in ihrer Planeinheit.
public struct MacroActualWeek: Codable, Equatable, Sendable {
    public struct Sport: Codable, Equatable, Sendable {
        public let sport: SportID
        public let amount: Double
        public let sessions: Int

        public init(sport: SportID, amount: Double, sessions: Int) {
            self.sport = sport
            self.amount = amount
            self.sessions = sessions
        }
    }

    public let weekStart: String
    public let sports: [Sport]

    public init(weekStart: String, sports: [Sport]) {
        self.weekStart = weekStart
        self.sports = sports
    }

    public func amount(of sport: SportID) -> Double {
        sports.first { $0.sport == sport }?.amount ?? 0
    }
}

/// Plan gegen Ist: rechnet die Wochen des Gesamtplans aus den Einheiten nach und erkennt schwache Wochen.
public struct MacroActualCalculator: Sendable {
    /// Unter so viel Prozent des Plans gilt eine Woche als schwach.
    public static let lowCompliancePercent = 60
    /// Nach so vielen schwachen Wochen nacheinander schlägt die App eine Fortschreibung vor.
    public static let lowComplianceWeeks = 2

    public let registry: SportRegistry
    public let calendar: Calendar
    private let weekCalendar: WeekCalendar

    public init(registry: SportRegistry = .standard, calendar: Calendar = .current) {
        self.registry = registry
        self.calendar = calendar
        self.weekCalendar = WeekCalendar(calendar: calendar)
    }

    /// Das Ist der Wochen `weekStarts` aus `workouts`, in der Planeinheit jeder Sportart (Meter oder Minuten).
    public func actualWeeks(_ weekStarts: [String], workouts: [Workout]) -> [MacroActualWeek] {
        let deduplicated = WorkoutDeduplicator.deduplicate(workouts)
        return weekStarts.map { start in
            let inWeek = deduplicated.filter { weekCalendar.weekStart(containing: $0.startDate) == start }
            let sports = registry.ids.compactMap { sport -> MacroActualWeek.Sport? in
                let sessions = inWeek.filter { $0.sport == sport }
                guard !sessions.isEmpty else { return nil }
                let unit = registry.module(for: sport)?.planUnit ?? .minutes
                let amount = sessions.reduce(0.0) { total, workout in
                    total + (unit == .meters ? (workout.distanceMeters ?? 0) : workout.duration / 60)
                }
                return MacroActualWeek.Sport(sport: sport, amount: amount.rounded(), sessions: sessions.count)
            }
            return MacroActualWeek(weekStart: start, sports: sports)
        }
    }

    /// Erfüllung in Prozent, `nil` ohne Plan für die Sportart.
    public static func percent(planned: Double, actual: Double) -> Int? {
        guard planned > 0 else { return nil }
        return Int((actual / planned * 100).rounded())
    }

    /// Sportarten, die in den letzten zwei abgeschlossenen Wochen vor `currentWeekStart` jeweils unter 60 % des Plans
    /// lagen. Wochen ohne Plan für die Sportart zählen nicht.
    public func lowComplianceSports(plan: MacroPlanV2, actual: [MacroActualWeek], currentWeekStart: String) -> [SportID] {
        let past = plan.weeks.filter { $0.weekStart < currentWeekStart }.suffix(Self.lowComplianceWeeks)
        guard past.count == Self.lowComplianceWeeks else { return [] }
        return registry.ids.filter { sport in
            past.allSatisfy { week in
                guard let planned = week.volume(of: sport)?.amount, planned > 0 else { return false }
                let done = actual.first { $0.weekStart == week.weekStart }?.amount(of: sport) ?? 0
                return (Self.percent(planned: planned, actual: done) ?? 100) < Self.lowCompliancePercent
            }
        }
    }
}

/// Eine gemeldete Pause (krank, verletzt, Urlaub). Ab 7 Tagen schreibt die App den Gesamtplan außer der Reihe fort.
public struct PauseReport: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        case sick, injury, vacation, other

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .sick: return "Krank"
            case .injury: return "Verletzt"
            case .vacation: return "Urlaub"
            case .other: return "Sonstiges"
            }
        }
    }

    /// Ab so vielen Tagen löst eine Pause eine Fortschreibung aus.
    public static let reviewDays = 7

    public let id: UUID
    public let kind: Kind
    /// Erster Tag, `yyyy-MM-dd`.
    public let from: String
    /// Letzter Tag, `nil`: noch nicht vorbei.
    public let to: String?
    public let reportedAt: Date

    public init(id: UUID = UUID(), kind: Kind, from: String, to: String?, reportedAt: Date) {
        self.id = id
        self.kind = kind
        self.from = from
        self.to = to
        self.reportedAt = reportedAt
    }

    /// Tage der Pause; eine laufende zählt als mindestens so lang wie die Schwelle (sie dauert ja noch).
    public func days(calendar: Calendar = .current) -> Int {
        let weekCalendar = WeekCalendar(calendar: calendar)
        guard let start = weekCalendar.date(from: from) else { return 0 }
        guard let to, let end = weekCalendar.date(from: to) else { return Self.reviewDays }
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    public func triggersReview(calendar: Calendar = .current) -> Bool {
        days(calendar: calendar) >= Self.reviewDays
    }

    public var problem: String? {
        if let to, to < from { return "Das Ende liegt vor dem Anfang." }
        return nil
    }
}

/// Speichert die zuletzt gemeldete Pause und ob sie schon zu einer Fortschreibung geführt hat.
public protocol PauseReportStoring {
    func report() -> PauseReport?
    func setReport(_ report: PauseReport?)
    /// Die Pause, die schon fortgeschrieben wurde.
    func reviewedReportID() -> UUID?
    func markReviewed(_ id: UUID)
}

public extension PauseReportStoring {
    /// Die gemeldete Pause, die noch eine Fortschreibung auslöst.
    func pendingReviewReport(calendar: Calendar = .current) -> PauseReport? {
        guard let report = report(), report.id != reviewedReportID(), report.triggersReview(calendar: calendar) else { return nil }
        return report
    }
}

public struct UserDefaultsPauseReportStore: PauseReportStoring {
    static let reportKey = "settings.pauseReport"
    static let reviewedKey = "settings.pauseReport.reviewed"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func report() -> PauseReport? {
        guard let data = defaults.data(forKey: Self.reportKey) else { return nil }
        return try? JSONDecoder().decode(PauseReport.self, from: data)
    }

    public func setReport(_ report: PauseReport?) {
        guard let report, report.problem == nil, let data = try? JSONEncoder().encode(report) else {
            if report == nil { defaults.removeObject(forKey: Self.reportKey) }
            return
        }
        defaults.set(data, forKey: Self.reportKey)
    }

    public func reviewedReportID() -> UUID? {
        defaults.string(forKey: Self.reviewedKey).flatMap(UUID.init(uuidString:))
    }

    public func markReviewed(_ id: UUID) {
        defaults.set(id.uuidString, forKey: Self.reviewedKey)
    }
}
