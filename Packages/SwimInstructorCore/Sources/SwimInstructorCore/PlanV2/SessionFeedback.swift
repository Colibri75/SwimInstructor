import Foundation

/// Beschwerden nach einer Einheit, wie der Athlet sie meldet. Der Server bremst die Sportart danach für einige Tage
/// (leicht 1 Tag keine harte Einheit, deutlich 2 Tage nur locker, stark 3 Tage Pause in dieser Sportart).
public enum PainLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    case none = 0
    case light = 1
    case moderate = 2
    case strong = 3

    public var displayName: String {
        switch self {
        case .none: return "Keine"
        case .light: return "Leicht"
        case .moderate: return "Deutlich"
        case .strong: return "Stark"
        }
    }

    /// Für "leichte Beschwerden", "deutliche Beschwerden".
    public var adjective: String {
        switch self {
        case .none: return "keine"
        case .light: return "leichte"
        case .moderate: return "deutliche"
        case .strong: return "starke"
        }
    }

    public static func < (lhs: PainLevel, rhs: PainLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Wo die Beschwerden sitzen. Die Rohwerte sind die des Servers (`pain_area`).
public enum PainArea: String, Codable, Sendable, CaseIterable, Identifiable {
    case knee, shin, achilles, foot, hip, back, shoulder, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .knee: return "Knie"
        case .shin: return "Schienbein"
        case .achilles: return "Achillessehne"
        case .foot: return "Fuß"
        case .hip: return "Hüfte"
        case .back: return "Rücken"
        case .shoulder: return "Schulter"
        case .other: return "Anderswo"
        }
    }
}

/// Die Rückmeldung des Athleten zu einer Einheit aus Health: gefühlte Anstrengung (1 bis 10) und Beschwerden.
public struct SessionFeedback: Codable, Equatable, Sendable, Identifiable {
    public let workoutID: UUID
    /// Kalendertag der Einheit, `yyyy-MM-dd`.
    public let date: String
    public let sport: SportID
    /// Gefühlte Anstrengung 1 bis 10, `nil` ohne Angabe.
    public let effort: Int?
    public let pain: PainLevel
    public let painArea: PainArea?
    public let recordedAt: Date

    public var id: UUID { workoutID }

    public static let effortRange: ClosedRange<Int> = 1...10

    public init(workoutID: UUID, date: String, sport: SportID, effort: Int?, pain: PainLevel, painArea: PainArea?, recordedAt: Date) {
        self.workoutID = workoutID
        self.date = date
        self.sport = sport
        self.effort = effort.map { min(max($0, Self.effortRange.lowerBound), Self.effortRange.upperBound) }
        self.pain = pain
        self.painArea = pain == .none ? nil : painArea
        self.recordedAt = recordedAt
    }
}

public protocol SessionFeedbackStoring {
    func all() -> [SessionFeedback]
    func save(_ feedback: SessionFeedback) throws
}

/// Die Rückmeldungen der letzten Wochen in `session-feedback.json`; je Einheit zählt die letzte.
public struct FileSessionFeedbackStore: SessionFeedbackStoring {
    public static let keepDays = 60

    private let fileURL: URL
    private let now: () -> Date
    private let calendar: Calendar

    public init(fileURL: URL, now: @escaping () -> Date = { Date() }, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.now = now
        self.calendar = calendar
    }

    public static func standard() -> FileSessionFeedbackStore {
        FileSessionFeedbackStore(fileURL: PlanV2Files.url("session-feedback.json"))
    }

    public func all() -> [SessionFeedback] {
        (PlanV2Files.read([SessionFeedback].self, from: fileURL) ?? []).sorted { $0.date < $1.date }
    }

    public func save(_ feedback: SessionFeedback) throws {
        let oldest = calendar.date(byAdding: .day, value: -Self.keepDays, to: now()).map { PlanFormatting.isoDay($0, calendar: calendar) } ?? ""
        let kept = all().filter { $0.workoutID != feedback.workoutID && $0.date >= oldest }
        try PlanV2Files.write(kept + [feedback], to: fileURL)
    }
}

// MARK: - Plan reagiert auf das echte Training

/// Warum die App die sieben Tage neu plant. Die Rohwerte sind die des Servers (`reason`).
public enum ReplanReason: String, Codable, Sendable {
    case daily, missed, effort, pain, manual
}

/// Eine geplante Einheit der letzten Tage, die ausgefallen ist (`missed_sessions`).
public struct MissedSession: Codable, Equatable, Sendable {
    public let date: String
    public let sport: SportID
    public let sessionType: SessionType
    public let intensity: PlanIntensity
    public let amount: Double

    public init(date: String, sport: SportID, sessionType: SessionType, intensity: PlanIntensity, amount: Double) {
        self.date = date
        self.sport = sport
        self.sessionType = sessionType
        self.intensity = intensity
        self.amount = amount
    }
}

/// Ein Anlass, die sieben Tage sofort neu abzustimmen, mit einem Schlüssel, damit derselbe Anlass nur einmal zählt.
public struct AdaptationSignal: Equatable, Sendable {
    public let reason: ReplanReason
    public let key: String

    public init(reason: ReplanReason, key: String) {
        self.reason = reason
        self.key = key
    }
}

public enum Adaptation {
    /// Ab dieser gefühlten Anstrengung gilt eine Einheit als deutlich zu hart (wie beim Server ab 8 "hart").
    public static let hardEffort = 8
    /// So viele Tage zurück zählen Ausfälle und Rückmeldungen.
    public static let lookbackDays = 7

    /// Geplante Einheiten der letzten `lookbackDays` Tage vor heute, für deren Sportart an dem Tag keine Einheit in
    /// Health steht. Tage ohne Zeit zählen nicht.
    public static func missedSessions(weeks: [WeekPlanV2], workouts: [Workout], today: String, calendar: Calendar = .current) -> [MissedSession] {
        let weekCalendar = WeekCalendar(calendar: calendar)
        guard let oldest = weekCalendar.addingDays(-lookbackDays, to: today) else { return [] }
        let done = Set(workouts.map { "\(PlanFormatting.isoDay($0.startDate, calendar: calendar))|\($0.sport.rawValue)" })
        return weeks
            .flatMap(\.days)
            .filter { $0.date >= oldest && $0.date < today && !$0.isUnavailable }
            .sorted { $0.date < $1.date }
            .flatMap { day in
                day.sessions
                    // Unbekannte Werte (neuerer Server) nimmt der Server in der Anfrage nicht an.
                    .filter { $0.sessionType != .unknown && $0.intensity != .unknown }
                    .filter { !done.contains("\(day.date)|\($0.sport.rawValue)") }
                    .map { MissedSession(date: day.date, sport: $0.sport, sessionType: $0.sessionType, intensity: $0.intensity, amount: $0.amount) }
            }
    }

    /// Der wichtigste neue Anlass: Beschwerden (ab deutlich) vor einer sehr harten Einheit vor einem Ausfall gestern.
    /// Schon behandelte Schlüssel (`handled`) zählen nicht.
    public static func signal(
        feedback: [SessionFeedback],
        missed: [MissedSession],
        workouts: [Workout],
        today: String,
        handled: Set<String>,
        calendar: Calendar = .current
    ) -> AdaptationSignal? {
        let weekCalendar = WeekCalendar(calendar: calendar)
        let yesterday = weekCalendar.addingDays(-1, to: today) ?? today
        let recent = feedback.filter { $0.date >= yesterday && $0.date <= today }

        let pain = recent
            .filter { $0.pain >= .moderate }
            .map { AdaptationSignal(reason: .pain, key: "pain|\($0.workoutID.uuidString)|\($0.pain.rawValue)") }
            .first { !handled.contains($0.key) }
        if let pain { return pain }

        // Sehr hart: eigene Angabe, sonst Health (eigene Bewertung oder Apples Schätzung).
        let rated = Dictionary(recent.map { ($0.workoutID, $0) }, uniquingKeysWith: { _, last in last })
        let hard = workouts
            .filter {
                let day = PlanFormatting.isoDay($0.startDate, calendar: calendar)
                return day >= yesterday && day <= today
            }
            .filter { workout in
                let effort = rated[workout.id]?.effort.map(Double.init) ?? workout[.effort]
                return (effort ?? 0) >= Double(hardEffort)
            }
            .map { AdaptationSignal(reason: .effort, key: "effort|\($0.id.uuidString)") }
            .first { !handled.contains($0.key) }
        if let hard { return hard }

        let missedYesterday = missed.filter { $0.date == yesterday }
        if !missedYesterday.isEmpty {
            let signal = AdaptationSignal(reason: .missed, key: "missed|\(yesterday)|\(missedYesterday.map(\.sport.rawValue).sorted().joined(separator: ","))")
            if !handled.contains(signal.key) { return signal }
        }
        return nil
    }
}

/// Welche Anlässe schon zu einer Neuplanung geführt haben (damit derselbe nicht jedes Öffnen neu plant).
public protocol AdaptationMarking {
    func handled() -> Set<String>
    func markHandled(_ key: String)
}

public struct UserDefaultsAdaptationMarker: AdaptationMarking {
    static let storageKey = "plan.adaptationKeys"
    /// So viele Schlüssel bleiben gespeichert.
    static let keep = 50

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func handled() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    public func markHandled(_ key: String) {
        var keys = (defaults.stringArray(forKey: Self.storageKey) ?? []).filter { $0 != key }
        keys.append(key)
        defaults.set(Array(keys.suffix(Self.keep)), forKey: Self.storageKey)
    }
}
