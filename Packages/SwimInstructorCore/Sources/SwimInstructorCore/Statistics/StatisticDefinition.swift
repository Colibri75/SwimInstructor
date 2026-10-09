import Foundation

/// Kennung einer Kennzahl der Statistik, z. B. `pace_per_km`. Offen wie `SportID`: Ein Modul kann eigene Kennzahlen
/// mitbringen. Die Kennung steht in der gespeicherten Anordnung der Kacheln und darf sich deshalb nicht ändern.
public struct StatisticMetric: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

public extension StatisticMetric {
    static let distance: StatisticMetric = "distance"
    static let duration: StatisticMetric = "duration"
    static let sessions: StatisticMetric = "sessions"
    static let longestDistance: StatisticMetric = "longest_distance"
    static let longestDuration: StatisticMetric = "longest_duration"
    static let pacePerHundredMeters: StatisticMetric = "pace_per_100m"
    static let pacePerKilometer: StatisticMetric = "pace_per_km"
    static let speed: StatisticMetric = "speed"
    static let averageHeartRate: StatisticMetric = "average_heart_rate"
    static let averagePower: StatisticMetric = "average_power"
    static let averageCadence: StatisticMetric = "average_cadence"
    static let elevationGain: StatisticMetric = "elevation_gain"
    static let trainingLoad: StatisticMetric = "training_load"
    static let restingHeartRate: StatisticMetric = "resting_heart_rate"
    static let heartRateVariability: StatisticMetric = "heart_rate_variability"
    static let sleep: StatisticMetric = "sleep"
    static let planAdherence: StatisticMetric = "plan_adherence"
}

/// Was eine Kennzahl aus den Einheiten, Tageswerten oder Plänen eines Zeitraums rechnet.
public enum StatisticMeasure: Sendable, Equatable {
    /// Summe der Strecke in Metern.
    case distance
    /// Summe der Dauer in Sekunden.
    case duration
    /// Anzahl der Einheiten.
    case sessions
    /// Längste Strecke einer Einheit in Metern.
    case longestDistance
    /// Längste Dauer einer Einheit in Sekunden.
    case longestDuration
    /// Sekunden pro `meters`: Gesamtzeit durch Gesamtstrecke der Einheiten mit Strecke. Für eine einzelne Einheit ist das
    /// dieselbe Pace wie in der Fitness-App.
    case pace(meters: Double)
    /// Meter pro Sekunde: Gesamtstrecke durch Gesamtzeit der Einheiten mit Strecke.
    case speed
    /// Mittlerer Puls der Einheiten mit Puls, nach Dauer gewichtet.
    case averageHeartRate
    /// Summe eines Zusatzwerts (Höhenmeter, Züge).
    case total(WorkoutMetric)
    /// Mittel eines Zusatzwerts, nach Dauer gewichtet (Watt, Trittfrequenz).
    case average(WorkoutMetric)
    /// Zusatzwert pro `meters` Strecke (etwa Züge pro 100 m), aus den Einheiten mit Wert und Strecke.
    case perDistance(WorkoutMetric, meters: Double)
    /// Summe der Belastung nach `TrainingLoadCalculator`.
    case trainingLoad
    /// Mittel der Tage mit Messung.
    case restingHeartRate
    /// Mittel der Tage mit Messung (SDNN in ms).
    case heartRateVariability
    /// Mittlere Schlafdauer der Nächte mit Aufzeichnung, in Sekunden.
    case sleep
    /// Anteil der vergangenen geplanten Trainingstage, an denen trainiert wurde (0 bis 1), wie im Verlauf.
    case planAdherence

    /// Summen wachsen mit dem Zeitraum: Der Verlauf zeigt sie als Balken, Mittelwerte als Linie.
    public var isTotal: Bool {
        switch self {
        case .distance, .duration, .sessions, .total, .trainingLoad: return true
        default: return false
        }
    }

    /// Rechnet aus den Einheiten (und passt damit zu einer Sportart); sonst aus Tageswerten oder Plänen.
    public var usesWorkouts: Bool {
        switch self {
        case .restingHeartRate, .heartRateVariability, .sleep, .planAdherence: return false
        default: return true
        }
    }
}

/// Wie der Wert einer Kennzahl als Text erscheint (`StatisticFormatting`).
public enum StatisticFormat: Sendable, Equatable {
    /// Meter mit Tausenderpunkt: "12.400".
    case meters
    /// Kilometer aus Metern mit einer Nachkommastelle: "123,4".
    case kilometers
    /// Stunden und Minuten aus Sekunden: "5:30".
    case hours
    /// Minuten und Sekunden aus Sekunden: "5:12".
    case pace
    /// km/h aus m/s mit einer Nachkommastelle: "28,4".
    case kilometersPerHour
    /// Ganze Zahl mit Tausenderpunkt: "142", "1.240".
    case integer
    /// Prozent aus einem Anteil: "85".
    case percent
}

/// Eine Kennzahl, die eine Kachel zeigen kann. Die Kennzahlen je Sportart stehen im Modul (`SportModule.statistics`),
/// die über alle Sportarten in `StatisticDefinition.overall`.
public struct StatisticDefinition: Sendable, Equatable, Identifiable {
    public let metric: StatisticMetric
    /// Deutscher Name für Kachel und Auswahl, z. B. "Pace pro km".
    public let displayName: String
    /// Einheit hinter dem Wert, leer für Anzahlen.
    public let unit: String
    public let measure: StatisticMeasure
    public let format: StatisticFormat
    /// Ob ein höherer Wert besser ist (`true`), ein niedrigerer (`false`, etwa Pace und Ruhepuls) oder keins von beiden
    /// (`nil`, etwa Umfang: mehr ist nicht immer besser). Färbt den Vergleich mit dem Zeitraum davor.
    public let higherIsBetter: Bool?

    public var id: StatisticMetric { metric }

    public init(
        metric: StatisticMetric,
        displayName: String,
        unit: String,
        measure: StatisticMeasure,
        format: StatisticFormat,
        higherIsBetter: Bool? = nil
    ) {
        self.metric = metric
        self.displayName = displayName
        self.unit = unit
        self.measure = measure
        self.format = format
        self.higherIsBetter = higherIsBetter
    }
}

// MARK: - Bausteine für die Kataloge der Module

public extension StatisticDefinition {
    static let distanceMeters = StatisticDefinition(metric: .distance, displayName: String(localized: "Umfang"), unit: "m", measure: .distance, format: .meters)
    static let distanceKilometers = StatisticDefinition(metric: .distance, displayName: String(localized: "Umfang"), unit: "km", measure: .distance, format: .kilometers)
    static let duration = StatisticDefinition(metric: .duration, displayName: String(localized: "Zeit"), unit: "h", measure: .duration, format: .hours)
    static let sessions = StatisticDefinition(metric: .sessions, displayName: String(localized: "Einheiten", comment: "Anzahl der Trainingseinheiten"), unit: "", measure: .sessions, format: .integer)
    static let longestDistanceMeters = StatisticDefinition(
        metric: .longestDistance, displayName: String(localized: "Längste Einheit"), unit: "m", measure: .longestDistance, format: .meters, higherIsBetter: true
    )
    static let longestDistanceKilometers = StatisticDefinition(
        metric: .longestDistance, displayName: String(localized: "Längste Einheit"), unit: "km", measure: .longestDistance, format: .kilometers, higherIsBetter: true
    )
    static let longestDuration = StatisticDefinition(
        metric: .longestDuration, displayName: String(localized: "Längste Einheit"), unit: "h", measure: .longestDuration, format: .hours, higherIsBetter: true
    )
    static let pacePerHundredMeters = StatisticDefinition(
        metric: .pacePerHundredMeters, displayName: String(localized: "Pace pro 100 m"), unit: "/100 m", measure: .pace(meters: 100), format: .pace, higherIsBetter: false
    )
    static let pacePerKilometer = StatisticDefinition(
        metric: .pacePerKilometer, displayName: String(localized: "Pace pro km"), unit: "/km", measure: .pace(meters: 1000), format: .pace, higherIsBetter: false
    )
    static let speed = StatisticDefinition(
        metric: .speed, displayName: String(localized: "Tempo"), unit: "km/h", measure: .speed, format: .kilometersPerHour, higherIsBetter: true
    )
    static let averageHeartRate = StatisticDefinition(
        metric: .averageHeartRate, displayName: String(localized: "Ø Puls"), unit: "bpm", measure: .averageHeartRate, format: .integer
    )
    static let averagePower = StatisticDefinition(
        metric: .averagePower, displayName: String(localized: "Ø Leistung"), unit: "W", measure: .average(.averagePower), format: .integer, higherIsBetter: true
    )
    static let averageCadence = StatisticDefinition(
        metric: .averageCadence, displayName: String(localized: "Ø Trittfrequenz"), unit: String(localized: "U/min", comment: "Umdrehungen pro Minute (Trittfrequenz)"), measure: .average(.averageCadence), format: .integer
    )
    static let elevationGain = StatisticDefinition(
        metric: .elevationGain, displayName: String(localized: "Höhenmeter"), unit: String(localized: "Hm", comment: "Höhenmeter"), measure: .total(.elevationGain), format: .integer
    )
    static let trainingLoad = StatisticDefinition(
        metric: .trainingLoad, displayName: String(localized: "Trainingslast"), unit: String(localized: "Punkte", comment: "Einheit der Trainingslast"), measure: .trainingLoad, format: .integer
    )

    /// Für einen Zusatzwert aus Health die passende Kennzahl; `nil` für Werte ohne eigene Kennzahl (etwa Bahnen).
    static func forWorkoutMetric(_ metric: WorkoutMetric) -> StatisticDefinition? {
        [averagePower, averageCadence, elevationGain].first { $0.measure == .average(metric) || $0.measure == .total(metric) }
    }
}

// MARK: - Über alle Sportarten

public extension StatisticDefinition {
    static let hoursBySport = StatisticDefinition(
        metric: .duration, displayName: String(localized: "Stunden je Sportart"), unit: "h", measure: .duration, format: .hours
    )
    static let restingHeartRate = StatisticDefinition(
        metric: .restingHeartRate, displayName: String(localized: "Ruhepuls"), unit: "bpm", measure: .restingHeartRate, format: .integer, higherIsBetter: false
    )
    static let heartRateVariability = StatisticDefinition(
        metric: .heartRateVariability, displayName: String(localized: "HRV"), unit: "ms", measure: .heartRateVariability, format: .integer, higherIsBetter: true
    )
    static let sleep = StatisticDefinition(
        metric: .sleep, displayName: String(localized: "Schlaf"), unit: "h", measure: .sleep, format: .hours, higherIsBetter: true
    )
    static let planAdherence = StatisticDefinition(
        metric: .planAdherence, displayName: String(localized: "Plan erfüllt"), unit: "%", measure: .planAdherence, format: .percent, higherIsBetter: true
    )

    /// Die Kennzahlen über alle Sportarten; die erste ist der Standard, wenn eine gespeicherte Kennzahl wegfällt.
    static let overall: [StatisticDefinition] = [
        hoursBySport, trainingLoad, sessions, planAdherence, restingHeartRate, heartRateVariability, sleep
    ]
}
