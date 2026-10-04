import Foundation

/// Umfang einer Sportart in einer Woche des Gesamtplans v2.
public struct MacroSportVolume: Codable, Equatable, Sendable {
    public let sport: SportID
    public let unit: PlanUnit
    /// Wochenumfang in `unit`.
    public let amount: Double
    public let minutes: Double
    public let distanceMeters: Double
    public let sessions: Int

    public init(sport: SportID, unit: PlanUnit, amount: Double, minutes: Double, distanceMeters: Double, sessions: Int) {
        self.sport = sport
        self.unit = unit
        self.amount = amount
        self.minutes = minutes
        self.distanceMeters = distanceMeters
        self.sessions = sessions
    }
}

/// Ein Leistungstest, den der Gesamtplan in einer Woche vorsieht. Den Termin setzt der Server.
public struct MacroTestSlot: Codable, Equatable, Sendable {
    public let sport: SportID
    public let testID: String
    public let displayName: String

    public init(sport: SportID, testID: String, displayName: String) {
        self.sport = sport
        self.testID = testID
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case sport
        case testID = "testId"
        case displayName
    }
}

/// Eine Woche des Gesamtplans v2: Phase, Entlastung, Umfang je Sportart und Testtermine. Geht unverändert als Vorgabe an
/// den Wochenplan und als bisheriger Plan an die Überarbeitung; der Server liest davon, was er braucht.
public struct MacroWeekV2: Codable, Equatable, Sendable, Identifiable {
    /// Montag der Woche, `yyyy-MM-dd`.
    public let weekStart: String
    public let phase: MacroPhase
    public let deload: Bool
    public let focus: String
    public let totalMinutes: Double
    public let load: Double
    public let sports: [MacroSportVolume]
    public let tests: [MacroTestSlot]

    public var id: String { weekStart }

    public init(
        weekStart: String,
        phase: MacroPhase,
        deload: Bool,
        focus: String,
        totalMinutes: Double,
        load: Double,
        sports: [MacroSportVolume],
        tests: [MacroTestSlot] = []
    ) {
        self.weekStart = weekStart
        self.phase = phase
        self.deload = deload
        self.focus = focus
        self.totalMinutes = totalMinutes
        self.load = load
        self.sports = sports
        self.tests = tests
    }

    private enum CodingKeys: String, CodingKey {
        case weekStart, phase, deload, focus, totalMinutes, load, sports, tests
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try container.decode(String.self, forKey: .weekStart)
        phase = try container.decode(MacroPhase.self, forKey: .phase)
        deload = try container.decode(Bool.self, forKey: .deload)
        focus = try container.decodeIfPresent(String.self, forKey: .focus) ?? ""
        totalMinutes = try container.decodeIfPresent(Double.self, forKey: .totalMinutes) ?? 0
        load = try container.decodeIfPresent(Double.self, forKey: .load) ?? 0
        sports = try container.decode([MacroSportVolume].self, forKey: .sports)
        tests = try container.decodeIfPresent([MacroTestSlot].self, forKey: .tests) ?? []
    }

    public func volume(of sport: SportID) -> MacroSportVolume? {
        sports.first { $0.sport == sport }
    }
}

/// Eine Runde Feedback zum Gesamtplan: was der Athlet geschrieben hat und was Claude daraufhin geändert hat.
public struct MacroFeedbackRound: Codable, Equatable, Sendable {
    public let feedback: String
    public let changes: [String]
    /// Korrekturen der Sicherheitsschicht an der Überarbeitung.
    public let adjustments: [String]
    public let revisedAt: Date

    public init(feedback: String, changes: [String], adjustments: [String] = [], revisedAt: Date) {
        self.feedback = feedback
        self.changes = changes
        self.adjustments = adjustments
        self.revisedAt = revisedAt
    }
}

/// Der Gesamtplan v2 bis zum Zieltag, wie ihn die App hält, mit den Feedback-Runden. Der Server speichert ihn nicht.
public struct MacroPlanV2: Codable, Equatable, Sendable {
    /// Wofür er geplant wurde (`TrainingGoal.planKey`): Ändert sich das Ziel, ist er veraltet.
    public var goalKey: String
    /// Der Zieltag, `yyyy-MM-dd`.
    public var goalDay: String
    public var generatedAt: Date
    public var rationale: String
    public var adjustments: [String]
    /// Aufsteigend nach Wochenbeginn.
    public var weeks: [MacroWeekV2]
    /// Feedback-Runden zu diesem Plan, älteste zuerst. Ein neu berechneter Plan beginnt ohne.
    public var feedbackRounds: [MacroFeedbackRound]

    public init(
        goalKey: String,
        goalDay: String,
        generatedAt: Date,
        rationale: String,
        adjustments: [String] = [],
        weeks: [MacroWeekV2],
        feedbackRounds: [MacroFeedbackRound] = []
    ) {
        self.goalKey = goalKey
        self.goalDay = goalDay
        self.generatedAt = generatedAt
        self.rationale = rationale
        self.adjustments = adjustments
        self.weeks = weeks.sorted { $0.weekStart < $1.weekStart }
        self.feedbackRounds = feedbackRounds
    }

    private enum CodingKeys: String, CodingKey {
        case goalKey, goalDay, generatedAt, rationale, adjustments, weeks, feedbackRounds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            goalKey: try container.decode(String.self, forKey: .goalKey),
            goalDay: try container.decode(String.self, forKey: .goalDay),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            rationale: try container.decode(String.self, forKey: .rationale),
            adjustments: try container.decodeIfPresent([String].self, forKey: .adjustments) ?? [],
            weeks: try container.decode([MacroWeekV2].self, forKey: .weeks),
            feedbackRounds: try container.decodeIfPresent([MacroFeedbackRound].self, forKey: .feedbackRounds) ?? []
        )
    }

    public func week(starting weekStart: String) -> MacroWeekV2? {
        weeks.first { $0.weekStart == weekStart }
    }

    /// Wochen ab `weekStart` (einschließlich).
    public func weeks(from weekStart: String) -> [MacroWeekV2] {
        weeks.filter { $0.weekStart >= weekStart }
    }

    /// Die Sportarten des Plans in der Reihenfolge, in der sie zuerst vorkommen.
    public var sports: [SportID] {
        var seen = Set<SportID>()
        return weeks.flatMap(\.sports).map(\.sport).filter { seen.insert($0).inserted }
    }

    /// Höchster Wochenumfang einer Sportart in ihrer Einheit (der Höhepunkt vor dem Zuspitzen).
    public func peakAmount(of sport: SportID) -> Double {
        weeks.compactMap { $0.volume(of: sport)?.amount }.max() ?? 0
    }

    /// Höchste Wochenstunden über alle Sportarten, in Minuten.
    public var peakMinutes: Double {
        weeks.map(\.totalMinutes).max() ?? 0
    }

    /// Alle Testtermine mit ihrer Woche, in zeitlicher Reihenfolge.
    public var testSlots: [(weekStart: String, test: MacroTestSlot)] {
        weeks.flatMap { week in week.tests.map { (weekStart: week.weekStart, test: $0) } }
    }
}

/// Antwort von `POST /v1/plan/macro` (v2) und `POST /v1/plan/macro/revise`.
public struct MacroPlanV2Response: Decodable, Equatable, Sendable {
    public struct Plan: Decodable, Equatable, Sendable {
        public let rationale: String
        public let weeks: [MacroWeekV2]
    }

    public let planVersion: Int
    public let goalDay: String
    public let generatedAt: Date
    public let plan: Plan
    public let adjustments: [String]
    /// Nur bei der Überarbeitung: was sich gegenüber dem bisherigen Plan ändert.
    public let changes: [String]?
    /// Nur bei der Überarbeitung: das Feedback, so wie der Server es gelesen hat.
    public let feedback: String?

    /// Als gespeicherter Gesamtplan für das Ziel `goalKey`, mit den Feedback-Runden `rounds`.
    public func macroPlan(goalKey: String, feedbackRounds rounds: [MacroFeedbackRound] = []) -> MacroPlanV2 {
        MacroPlanV2(
            goalKey: goalKey,
            goalDay: goalDay,
            generatedAt: generatedAt,
            rationale: plan.rationale,
            adjustments: adjustments,
            weeks: plan.weeks,
            feedbackRounds: rounds
        )
    }
}

public extension TrainingGoal {
    /// Kennzeichnet das Ziel mit allem, was den Gesamtplan bestimmt (Disziplinen, Zieltag, Trainingstage, Stunden,
    /// Schwerpunkte). Ein Gesamtplan v2 gilt nur für genau dieses Ziel.
    func planKey(calendar: Calendar = .current) -> String {
        let disciplines = self.disciplines.map { discipline -> String in
            let duration = discipline.targetDurationSeconds.map { String(Int($0)) } ?? "-"
            return "\(discipline.sport.rawValue):\(Int(discipline.distanceMeters)):\(duration)"
        }.joined(separator: ",")
        let emphasis = self.emphasis.map { "\($0.sport.rawValue):\($0.percent)" }.joined(separator: ",")
        let day = PlanFormatting.isoDay(targetDate, calendar: calendar)
        return "\(disciplines)|\(day)|\(trainingDaysPerWeek)|\(weeklyHours)|\(emphasis)"
    }
}
