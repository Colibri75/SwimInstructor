import Foundation

/// Art der Einheit. Unbekannte Werte vom Server werden zu `.unknown`, damit eine neue Serverversion
/// die App nicht aus dem Tritt bringt.
public enum SessionType: String, Codable, Sendable, CaseIterable {
    case rest
    case recovery
    case technique
    case endurance
    case threshold
    case intervals
    case test
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionType(rawValue: raw) ?? .unknown
    }
}

public enum PlanIntensity: String, Codable, Sendable, CaseIterable {
    case rest
    case easy
    case moderate
    case hard
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlanIntensity(rawValue: raw) ?? .unknown
    }
}

/// Woher der Plan stammt (siehe docs/plan-generation.md).
public enum PlanSource: String, Codable, Sendable {
    /// Frisch von Claude erzeugt.
    case claude
    /// Heute schon für denselben Zustand erzeugt.
    case cache
    /// Letzter gültiger Plan, weil Claude nicht geantwortet hat.
    case fallback
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PlanSource(rawValue: raw) ?? .unknown
    }
}

/// Ein Abschnitt der Einheit, z. B. "6 × 200 m".
public struct PlanSet: Codable, Equatable, Sendable {
    public let name: String
    public let repetitions: Int
    public let distanceMeters: Int
    public let targetPaceSecondsPerHundredMeters: Double?
    public let restSeconds: Int
    public let instructions: String
    /// Hilfsmittel für diesen Abschnitt (`pull_buoy`, `paddles`, `fins`, `snorkel`, `kickboard`,
    /// `ankle_band`). Leer, wenn keine nötig sind und bei Plänen aus der Zeit vor dem Equipment.
    public let equipment: [String]

    public init(
        name: String,
        repetitions: Int,
        distanceMeters: Int,
        targetPaceSecondsPerHundredMeters: Double?,
        restSeconds: Int,
        instructions: String,
        equipment: [String] = []
    ) {
        self.name = name
        self.repetitions = repetitions
        self.distanceMeters = distanceMeters
        self.targetPaceSecondsPerHundredMeters = targetPaceSecondsPerHundredMeters
        self.restSeconds = restSeconds
        self.instructions = instructions
        self.equipment = equipment
    }

    private enum CodingKeys: String, CodingKey {
        case name, repetitions, distanceMeters, targetPaceSecondsPerHundredMeters, restSeconds, instructions, equipment
    }

    /// Eigenes Dekodieren, damit ein gespeicherter Plan ohne `equipment` (älterer Server, Cache auf dem
    /// Gerät) weiter lesbar bleibt, statt als kaputt zu gelten.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        repetitions = try container.decode(Int.self, forKey: .repetitions)
        distanceMeters = try container.decode(Int.self, forKey: .distanceMeters)
        targetPaceSecondsPerHundredMeters = try container.decodeIfPresent(Double.self, forKey: .targetPaceSecondsPerHundredMeters)
        restSeconds = try container.decode(Int.self, forKey: .restSeconds)
        instructions = try container.decode(String.self, forKey: .instructions)
        equipment = try container.decodeIfPresent([String].self, forKey: .equipment) ?? []
    }

    public var totalMeters: Int { repetitions * distanceMeters }
}

public struct TrainingPlan: Codable, Equatable, Sendable {
    public let sessionType: SessionType
    public let intensity: PlanIntensity
    public let rationale: String
    public let totalDistanceMeters: Int
    public let estimatedDurationMinutes: Int
    public let sets: [PlanSet]
    public let coachNotes: [String]

    public init(
        sessionType: SessionType,
        intensity: PlanIntensity,
        rationale: String,
        totalDistanceMeters: Int,
        estimatedDurationMinutes: Int,
        sets: [PlanSet],
        coachNotes: [String]
    ) {
        self.sessionType = sessionType
        self.intensity = intensity
        self.rationale = rationale
        self.totalDistanceMeters = totalDistanceMeters
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.sets = sets
        self.coachNotes = coachNotes
    }

    public var isRestDay: Bool { sessionType == .rest }

    /// Alle Hilfsmittel des Plans, ohne Doppelte, in der Reihenfolge, in der sie gebraucht werden.
    public var equipmentNeeded: [String] {
        var seen = Set<String>()
        return sets.flatMap(\.equipment).filter { seen.insert($0).inserted }
    }
}

/// Antwort von `POST /v1/plan/today`.
public struct PlanResponse: Codable, Equatable, Sendable {
    public let source: PlanSource
    /// Kalendertag des Plans als `YYYY-MM-DD` (Zeitzone des Servers).
    public let date: String
    public let generatedAt: Date
    /// `true`, wenn der Plan nicht von heute ist (nur bei `fallback`).
    public let stale: Bool
    public let plan: TrainingPlan
    /// Korrekturen der Sicherheitsschicht, auf Deutsch.
    public let adjustments: [String]
    /// Nur bei `fallback`: warum Claude nicht geantwortet hat.
    public let fallbackReason: String?
    /// Der Wunsch, mit dem der Server den Plan erzeugt hat. Fehlt bei einem Server ohne Wunsch-Unterstützung
    /// und bei Plänen ohne Wunsch: Wer einen Wunsch eingegeben hat und hier nichts sieht, weiß, dass er nicht ankam.
    public let wishes: String?

    public init(
        source: PlanSource,
        date: String,
        generatedAt: Date,
        stale: Bool,
        plan: TrainingPlan,
        adjustments: [String],
        fallbackReason: String? = nil,
        wishes: String? = nil
    ) {
        self.source = source
        self.date = date
        self.generatedAt = generatedAt
        self.stale = stale
        self.plan = plan
        self.adjustments = adjustments
        self.fallbackReason = fallbackReason
        self.wishes = wishes
    }
}

public extension PlanResponse {
    /// Der Server schreibt `generated_at` mit Millisekunden (`toISOString()`), das eingebaute
    /// `.iso8601` versteht die nicht. Darum ein eigener Decoder, der beide Formen annimmt.
    static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601Parsing.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Kein ISO-8601-Datum: \(raw)"
            )
        }
        return decoder
    }

    /// Zum Zwischenspeichern auf dem Gerät, passend zu `jsonDecoder()`.
    static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

enum ISO8601Parsing {
    static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
