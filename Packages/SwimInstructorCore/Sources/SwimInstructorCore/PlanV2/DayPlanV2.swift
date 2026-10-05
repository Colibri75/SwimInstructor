import Foundation

/// Ein Schritt einer Einheit in Plan v2, z. B. "4 × 50 m Abschlag" oder "3 × 1 min zügig". Maß und Ziel kommen aus dem
/// Wortschatz der Sportart (`contracts/sports.json`).
public struct PlanStep: Codable, Equatable, Sendable {
    public let name: String
    public let repetitions: Int
    /// `nil` bei einem Maß, das diese App-Version nicht kennt.
    public let measure: StepMeasure?
    /// Strecke je Wiederholung bei `distance`, sonst `nil`.
    public let distanceMeters: Int?
    /// Dauer je Wiederholung bei `duration`, sonst `nil`.
    public let durationSeconds: Int?
    /// `nil` ohne Ziel oder bei einem Ziel, das diese App-Version nicht kennt.
    public let targetType: StepTarget?
    /// Zielwert in der Einheit des Ziels (Sekunden pro 100 m oder km, Zone 1 bis 5, Watt, 1 bis 10).
    public let targetValue: Double?
    public let restSeconds: Int
    public let instructions: String
    /// Kurztext für die Uhr (zwei bis vier Wörter).
    public let cue: String
    public let equipment: [String]

    public init(
        name: String,
        repetitions: Int,
        measure: StepMeasure?,
        distanceMeters: Int? = nil,
        durationSeconds: Int? = nil,
        targetType: StepTarget? = nil,
        targetValue: Double? = nil,
        restSeconds: Int = 0,
        instructions: String = "",
        cue: String = "",
        equipment: [String] = []
    ) {
        self.name = name
        self.repetitions = repetitions
        self.measure = measure
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.targetType = targetType
        self.targetValue = targetValue
        self.restSeconds = restSeconds
        self.instructions = instructions
        self.cue = cue
        self.equipment = equipment
    }

    private enum CodingKeys: String, CodingKey {
        case name, repetitions, measure, distanceMeters, durationSeconds, targetType, targetValue
        case restSeconds, instructions, cue, equipment
    }

    /// Unbekannte Maße und Ziele (neuerer Server) fallen weg, statt den ganzen Plan unlesbar zu machen.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        repetitions = try container.decode(Int.self, forKey: .repetitions)
        measure = try container.decodeIfPresent(String.self, forKey: .measure).flatMap(StepMeasure.init(rawValue:))
        distanceMeters = try container.decodeIfPresent(Int.self, forKey: .distanceMeters)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        targetType = try container.decodeIfPresent(String.self, forKey: .targetType).flatMap(StepTarget.init(rawValue:))
        targetValue = try container.decodeIfPresent(Double.self, forKey: .targetValue)
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 0
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        cue = try container.decodeIfPresent(String.self, forKey: .cue) ?? ""
        equipment = try container.decodeIfPresent([String].self, forKey: .equipment) ?? []
    }

    /// Strecke aller Wiederholungen, 0 ohne Strecke.
    public var totalMeters: Int { repetitions * (distanceMeters ?? 0) }

    /// Dauer aller Wiederholungen ohne Pausen, 0 ohne Dauer.
    public var totalSeconds: Int { repetitions * (durationSeconds ?? 0) }
}

/// Ein Leistungstest im Plan: Die Einheit ist dann vom Typ `test`, die Schritte bringt das Modul mit.
public struct PlannedTest: Codable, Equatable, Sendable {
    /// Kennung des Tests innerhalb der Sportart (siehe `SportModule.performanceTests`).
    public let id: String
    public let displayName: String
    /// Vollbelastung: harter Tag, das Ergebnis gilt als getestet.
    public let maximalEffort: Bool
    /// Die Leistungswerte, die der Test ermittelt.
    public let produces: [PerformanceMetric]

    public init(id: String, displayName: String, maximalEffort: Bool, produces: [PerformanceMetric]) {
        self.id = id
        self.displayName = displayName
        self.maximalEffort = maximalEffort
        self.produces = produces
    }
}

/// Eine Einheit des Tagesplans v2 mit allen Schritten.
public struct DaySession: Codable, Equatable, Sendable {
    public let sport: SportID
    public let sessionType: SessionType
    public let intensity: PlanIntensity
    public let focus: String
    /// Gesetzt bei einem Leistungstest.
    public let test: PlannedTest?
    /// Umfang in der Einheit der Sportart (`unit`).
    public let amount: Double
    public let unit: PlanUnit
    public let distanceMeters: Double
    public let durationMinutes: Double
    public let steps: [PlanStep]

    public init(
        sport: SportID,
        sessionType: SessionType,
        intensity: PlanIntensity,
        focus: String,
        test: PlannedTest? = nil,
        amount: Double,
        unit: PlanUnit,
        distanceMeters: Double,
        durationMinutes: Double,
        steps: [PlanStep]
    ) {
        self.sport = sport
        self.sessionType = sessionType
        self.intensity = intensity
        self.focus = focus
        self.test = test
        self.amount = amount
        self.unit = unit
        self.distanceMeters = distanceMeters
        self.durationMinutes = durationMinutes
        self.steps = steps
    }

    /// Alle Hilfsmittel der Einheit, ohne Doppelte, in der Reihenfolge, in der sie gebraucht werden.
    public var equipmentNeeded: [String] {
        var seen = Set<String>()
        return steps.flatMap(\.equipment).filter { seen.insert($0).inserted }
    }
}

/// Der Tagesplan v2: null bis zwei Einheiten, eine Begründung und Hinweise.
public struct DayPlanV2: Codable, Equatable, Sendable {
    public let rationale: String
    /// Leer an einem Ruhetag.
    public let sessions: [DaySession]
    public let coachNotes: [String]

    public init(rationale: String, sessions: [DaySession], coachNotes: [String] = []) {
        self.rationale = rationale
        self.sessions = sessions
        self.coachNotes = coachNotes
    }

    public var isRestDay: Bool { sessions.isEmpty }

    /// Geplante Minuten aller Einheiten.
    public var totalMinutes: Double { sessions.reduce(0) { $0 + $1.durationMinutes } }

    /// Alle Hilfsmittel des Tages, ohne Doppelte.
    public var equipmentNeeded: [String] {
        var seen = Set<String>()
        return sessions.flatMap(\.equipmentNeeded).filter { seen.insert($0).inserted }
    }

    /// Die Einheiten einer Sportart.
    public func sessions(of sport: SportID) -> [DaySession] {
        sessions.filter { $0.sport == sport }
    }
}

/// Antwort von `POST /v1/plan/today` mit `plan_version: 2`, so auch im Cache und im Verlauf auf dem Gerät.
public struct DayPlanV2Response: Codable, Equatable, Sendable {
    /// Immer 2.
    public let planVersion: Int
    public let source: PlanSource
    /// Kalendertag des Plans als `yyyy-MM-dd` (Zeitzone des Servers).
    public let date: String
    public let generatedAt: Date
    /// `true`, wenn der Plan nicht von heute ist (nur bei `fallback`).
    public let stale: Bool
    public let plan: DayPlanV2
    /// Korrekturen der Sicherheitsschicht, auf Deutsch.
    public let adjustments: [String]
    /// Nur bei `fallback`: warum Claude nicht geantwortet hat.
    public let fallbackReason: String?
    /// Der Wunsch, mit dem der Server den Plan erzeugt hat.
    public let wishes: String?
    /// Nur in der App, nicht vom Server: die Vorgabe der sieben Tage, mit der die App den Plan geholt hat. Ändert sich die
    /// Vorgabe für heute (etwa der Umfang im Plan-Tab), passt der Plan nicht mehr dazu (`MultiSportTodayLoader`).
    public var requestedTarget: DayTargetV2?

    public init(
        planVersion: Int = 2,
        source: PlanSource,
        date: String,
        generatedAt: Date,
        stale: Bool,
        plan: DayPlanV2,
        adjustments: [String] = [],
        fallbackReason: String? = nil,
        wishes: String? = nil
    ) {
        self.planVersion = planVersion
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
