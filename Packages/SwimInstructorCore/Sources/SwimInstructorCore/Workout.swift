import Foundation

/// Zusatzwert einer Einheit, den nur manche Sportarten liefern (Bahnen, Züge, Watt, Höhenmeter ...). Offen wie
/// `SportID`: Ein neues Modul kann eigene Werte mitbringen, ohne dass der Kern sie kennen muss.
public struct WorkoutMetric: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }
}

public extension WorkoutMetric {
    /// Runden oder Bahnen (Runden-Ereignisse im Workout).
    static let laps: WorkoutMetric = "laps"
    /// Schwimmzüge gesamt.
    static let strokes: WorkoutMetric = "strokes"
    /// Mittlere Leistung in Watt.
    static let averagePower: WorkoutMetric = "average_power"
    /// Mittlere Trittfrequenz pro Minute.
    static let averageCadence: WorkoutMetric = "average_cadence"
    /// Höhenmeter bergauf.
    static let elevationGain: WorkoutMetric = "elevation_gain"
    /// Gefühlte Anstrengung der ganzen Einheit, 0 bis 10 (Session-RPE), aus Health: die eigene Bewertung oder, ohne sie,
    /// Apples Schätzung (ab iOS 18 / watchOS 11).
    static let effort: WorkoutMetric = "effort"
}

/// Eine Trainingseinheit irgendeiner Sportart, wie sie aus Health kommt. Was nur eine Sportart misst, steht in
/// `metrics`; die Sportart selbst entscheidet über ihr Modul, was davon wichtig ist.
public struct Workout: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sport: SportID
    public let startDate: Date
    public let endDate: Date
    public let duration: TimeInterval
    public let distanceMeters: Double?
    public let averageHeartRate: Double?
    public let activeEnergyKilocalories: Double?
    public let metrics: [WorkoutMetric: Double]

    public init(
        id: UUID,
        sport: SportID,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        metrics: [WorkoutMetric: Double] = [:]
    ) {
        self.id = id
        self.sport = sport
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.metrics = metrics
    }

    public subscript(metric: WorkoutMetric) -> Double? {
        metrics[metric]
    }
}
