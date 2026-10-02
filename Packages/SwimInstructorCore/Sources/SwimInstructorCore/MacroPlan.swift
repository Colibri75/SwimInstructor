import Foundation

/// Phase einer Woche im Gesamtplan. Der Server rechnet sie aus dem Abstand zum Zieltag.
public enum MacroPhase: String, Codable, Equatable, Sendable {
    case base
    case specific
    case taper
    case goalWeek = "goal_week"
    case maintain
}

/// Eine Woche des Gesamtplans: Richtung für den Umfang und den Schwerpunkt. Die Tage der Woche plant der
/// rollende 7-Tage-Plan, jeden Tag neu darauf abgestimmt.
public struct MacroWeek: Codable, Equatable, Sendable, Identifiable {
    /// Montag der Woche, `yyyy-MM-dd`.
    public let weekStart: String
    public let targetMeters: Int
    public let sessions: Int
    public let deload: Bool
    public let focus: String
    public let phase: MacroPhase

    public var id: String { weekStart }

    public init(weekStart: String, targetMeters: Int, sessions: Int, deload: Bool, focus: String, phase: MacroPhase) {
        self.weekStart = weekStart
        self.targetMeters = targetMeters
        self.sessions = sessions
        self.deload = deload
        self.focus = focus
        self.phase = phase
    }
}

/// Der Gesamtplan bis zum Zieltag, wie ihn die App hält. Der Server speichert ihn nicht.
public struct MacroPlan: Codable, Equatable, Sendable {
    /// Wofür er geplant wurde (Distanz, Zielzeit, Zieltag): ändert sich das Ziel, ist er veraltet.
    public var goalKey: String
    /// Der Zieltag, `yyyy-MM-dd`.
    public var goalDay: String
    public var generatedAt: Date
    public var rationale: String
    /// Korrekturen der Sicherheitsschicht des Servers, auf Deutsch.
    public var adjustments: [String]
    /// Aufsteigend nach Wochenbeginn.
    public var weeks: [MacroWeek]

    public init(goalKey: String, goalDay: String, generatedAt: Date, rationale: String, adjustments: [String] = [], weeks: [MacroWeek]) {
        self.goalKey = goalKey
        self.goalDay = goalDay
        self.generatedAt = generatedAt
        self.rationale = rationale
        self.adjustments = adjustments
        self.weeks = weeks.sorted { $0.weekStart < $1.weekStart }
    }

    public func week(starting weekStart: String) -> MacroWeek? {
        weeks.first { $0.weekStart == weekStart }
    }

    /// Höchster Wochenumfang des Plans (der Höhepunkt vor dem Zuspitzen).
    public var peakMeters: Int {
        weeks.map(\.targetMeters).max() ?? 0
    }

    /// Wochen ab `weekStart` (einschließlich).
    public func weeks(from weekStart: String) -> [MacroWeek] {
        weeks.filter { $0.weekStart >= weekStart }
    }
}

/// Antwort von `POST /v1/plan/macro`.
public struct MacroPlanResponse: Decodable, Equatable, Sendable {
    public struct Plan: Decodable, Equatable, Sendable {
        public let rationale: String
        public let weeks: [MacroWeek]
    }

    public let goalDay: String
    public let generatedAt: Date
    public let plan: Plan
    public let adjustments: [String]

    /// Als gespeicherter Gesamtplan, für das angegebene Ziel.
    public func macroPlan(goalKey: String) -> MacroPlan {
        MacroPlan(
            goalKey: goalKey,
            goalDay: goalDay,
            generatedAt: generatedAt,
            rationale: plan.rationale,
            adjustments: adjustments,
            weeks: plan.weeks
        )
    }
}

public extension AthleteGoal {
    /// Der Zieltag als `yyyy-MM-dd`.
    func goalDay(calendar: Calendar = .current) -> String {
        PlanFormatting.isoDay(targetDate, calendar: calendar)
    }

    /// Kennzeichnet das Ziel (Distanz, Zielzeit, Zieltag). Ein Gesamtplan gilt nur für genau dieses Ziel.
    func key(calendar: Calendar = .current) -> String {
        "\(Int(distanceMeters))-\(Int(targetDurationSeconds))-\(goalDay(calendar: calendar))"
    }
}

/// Hält den Gesamtplan auf dem Gerät.
public protocol MacroPlanStoring {
    func load() -> MacroPlan?
    func save(_ plan: MacroPlan) throws
}

public struct FileMacroPlanStore: MacroPlanStoring {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/SwimInstructor/macro-plan.json` im App-Container.
    public static func standard() -> FileMacroPlanStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileMacroPlanStore(fileURL: base.appendingPathComponent("SwimInstructor/macro-plan.json"))
    }

    public func load() -> MacroPlan? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        // Eine kaputte Datei ist kein Fehler, nur kein gespeicherter Gesamtplan.
        return try? PlanResponse.jsonDecoder().decode(MacroPlan.self, from: data)
    }

    public func save(_ plan: MacroPlan) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PlanResponse.jsonEncoder().encode(plan)
        try data.write(to: fileURL, options: .atomic)
    }
}
