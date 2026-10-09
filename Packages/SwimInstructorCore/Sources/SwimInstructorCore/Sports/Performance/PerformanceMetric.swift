import Foundation

/// Ein Leistungswert, nach dem sich Zonen und Tests richten (Maximalpuls, Schwellenpuls, CSS ...). Offen wie
/// `SportID`: Ein Modul bringt seine eigenen Werte mit, der Kern kennt nur die, die mehrere Sportarten teilen.
///
/// Die Kennungen sind Teil des Vertrags mit dem Server (`contracts/sports.json`).
public struct PerformanceMetric: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    /// Dieselben Regeln wie für eine Sport-Kennung.
    public var isWellFormed: Bool { SportID(rawValue: rawValue).isWellFormed }
}

public extension PerformanceMetric {
    /// Höchster Puls, gilt für alle Sportarten.
    static let maxHeartRate: PerformanceMetric = "max_heart_rate"
    /// Ruhepuls, gilt für alle Sportarten.
    static let restingHeartRate: PerformanceMetric = "resting_heart_rate"
    /// Puls an der Laktatschwelle (etwa der Schnitt einer 30-minütigen Vollbelastung), je Sportart verschieden.
    static let thresholdHeartRate: PerformanceMetric = "threshold_heart_rate"
    /// Leistung an der Schwelle in Watt (FTP), nur mit Leistungsmesser.
    static let thresholdPower: PerformanceMetric = "threshold_power"
}

/// Was ein Leistungswert bedeutet und welche Werte plausibel sind. App und Server prüfen dieselben Grenzen
/// (`contracts/sports.json`).
public struct PerformanceMetricDefinition: Sendable, Equatable {
    public let metric: PerformanceMetric
    /// Deutscher Name für die Anzeige, z. B. "Schwellenpuls".
    public let displayName: String
    /// Einheit wie im Vertrag: "bpm", "W", "s/100m", "s/km" oder "s".
    public let unit: String
    public let plausibleRange: ClosedRange<Double>
    /// Ob ein höherer gemessener Wert einen bestätigten ablöst. Beim Maximalpuls ist das so: Wer ihn im Training
    /// überschreitet, hat ihn erreicht, der alte Wert war zu niedrig.
    public let observedHigherWins: Bool

    public init(
        metric: PerformanceMetric,
        displayName: String,
        unit: String,
        plausibleRange: ClosedRange<Double>,
        observedHigherWins: Bool = false
    ) {
        self.metric = metric
        self.displayName = displayName
        self.unit = unit
        self.plausibleRange = plausibleRange
        self.observedHigherWins = observedHigherWins
    }
}

public extension PerformanceMetricDefinition {
    static let maxHeartRate = PerformanceMetricDefinition(
        metric: .maxHeartRate, displayName: String(localized: "Maximalpuls"), unit: "bpm", plausibleRange: 120...230, observedHigherWins: true
    )
    static let restingHeartRate = PerformanceMetricDefinition(
        metric: .restingHeartRate, displayName: String(localized: "Ruhepuls"), unit: "bpm", plausibleRange: 30...110
    )
    static let thresholdHeartRate = PerformanceMetricDefinition(
        metric: .thresholdHeartRate, displayName: String(localized: "Schwellenpuls"), unit: "bpm", plausibleRange: 100...215
    )
    static let thresholdPower = PerformanceMetricDefinition(
        metric: .thresholdPower, displayName: String(localized: "Schwellenleistung (FTP)"), unit: "W", plausibleRange: 50...600
    )

    /// Die Werte, die für alle Sportarten gelten (ohne Sportart im Profil).
    static let athlete: [PerformanceMetricDefinition] = [.maxHeartRate, .restingHeartRate]
}
