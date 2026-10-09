import Foundation

/// Ergänzungstraining neben den Sportarten: Kraft und Mobilität. Wie oft, legt der Athlet in den Einstellungen fest
/// (`Supplements`); der Server legt die Blöcke in die Woche und schreibt am Tag die Übungen.
public enum ExtraKind: String, Codable, Sendable, CaseIterable {
    case strength
    case mobility
    /// Eine Art, die diese App-Version nicht kennt (neuerer Server).
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExtraKind(rawValue: raw) ?? .unknown
    }

    /// Die Arten, die der Athlet einstellen kann.
    public static let selectable: [ExtraKind] = [.strength, .mobility]

    public var displayName: String {
        switch self {
        case .strength: return String(localized: "Kraft")
        case .mobility: return String(localized: "Mobilität")
        case .unknown: return String(localized: "Ergänzung")
        }
    }

    public var symbolName: String {
        switch self {
        case .strength: return "dumbbell"
        case .mobility: return "figure.flexibility"
        case .unknown: return "figure.mixed.cardio"
        }
    }
}

/// Ein Kraft- oder Mobilitätsblock im Plan der 14 Tage.
public struct WeekExtra: Codable, Equatable, Sendable {
    public var kind: ExtraKind
    public var minutes: Double
    public var focus: String

    public init(kind: ExtraKind, minutes: Double, focus: String) {
        self.kind = kind
        self.minutes = minutes
        self.focus = focus
    }
}

/// Eine Übung eines Blocks: Sätze mit Wiederholungen oder mit Dauer (Halten, Dehnen).
public struct Exercise: Codable, Equatable, Sendable {
    public let name: String
    public let sets: Int
    /// Wiederholungen je Satz, `nil` bei einer Übung nach Zeit.
    public let reps: Int?
    /// Dauer je Satz in Sekunden, `nil` bei einer Übung nach Wiederholungen.
    public let seconds: Int?
    public let restSeconds: Int
    public let cue: String
    public let instructions: String

    public init(name: String, sets: Int, reps: Int? = nil, seconds: Int? = nil, restSeconds: Int = 0, cue: String = "", instructions: String = "") {
        self.name = name
        self.sets = sets
        self.reps = reps
        self.seconds = seconds
        self.restSeconds = restSeconds
        self.cue = cue
        self.instructions = instructions
    }

    private enum CodingKeys: String, CodingKey {
        case name, sets, reps, seconds, restSeconds, cue, instructions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        sets = try container.decode(Int.self, forKey: .sets)
        reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        seconds = try container.decodeIfPresent(Int.self, forKey: .seconds)
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 0
        cue = try container.decodeIfPresent(String.self, forKey: .cue) ?? ""
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
    }

    /// "3 × 12" oder "2 × 30 s".
    public var summary: String {
        if let seconds { return "\(sets) × \(seconds) s" }
        return "\(sets) × \(reps ?? 1)"
    }
}

/// Ein Kraft- oder Mobilitätsblock im Tagesplan, mit Übungen.
public struct DayExtra: Codable, Equatable, Sendable {
    public let kind: ExtraKind
    public let minutes: Double
    public let focus: String
    public let exercises: [Exercise]

    public init(kind: ExtraKind, minutes: Double, focus: String, exercises: [Exercise]) {
        self.kind = kind
        self.minutes = minutes
        self.focus = focus
        self.exercises = exercises
    }
}
