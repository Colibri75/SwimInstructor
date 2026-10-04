import Foundation

/// Wie eine Sportart aus einem Leistungswert die Zonen eines Ziels rechnet, z. B. Pulszonen aus dem Schwellenpuls
/// oder Pace-Zonen aus der CSS. Die Zonen rechnet die App; der Server bekommt sie fertig im Snapshot.
public struct ZoneScheme: Sendable, Equatable {
    public enum Scale: Sendable, Equatable {
        /// Zonen als Anteil des Grundwerts (Puls, Watt): Zone 1 ist der kleinste Wert.
        case proportional
        /// Der Grundwert ist eine Zeit pro Strecke (Pace), die Grenzen sind Anteile der Geschwindigkeit: Zone 1 ist
        /// die langsamste, also die längste Zeit.
        case inversePace
    }

    public let target: StepTarget
    /// Grundwert der Sportart, sonst der für alle Sportarten (z. B. Maximalpuls).
    public let basis: PerformanceMetric
    public let scale: Scale
    /// Zonengrenzen als Anteil des Grundwerts, aufsteigend; n Grenzen ergeben n + 1 Zonen.
    public let bounds: [Double]

    public init(target: StepTarget, basis: PerformanceMetric, scale: Scale = .proportional, bounds: [Double]) {
        self.target = target
        self.basis = basis
        self.scale = scale
        self.bounds = bounds
    }

    /// Grenzen größer als 0 und streng aufsteigend.
    public var hasValidBounds: Bool {
        guard let first = bounds.first, first > 0 else { return false }
        return zip(bounds, bounds.dropFirst()).allSatisfy { $0 < $1 }
    }

    /// Die Zonen für einen Grundwert, gerundet auf ganze Einheiten (Schläge, Watt, Sekunden). Zone 1 ist nach unten
    /// offen, die letzte nach oben (bei Pace umgekehrt: Zone 1 ohne Höchstzeit, die letzte ohne schnellste Zeit).
    public func zones(basisValue: Double) -> TrainingZones {
        var zones: [TrainingZones.Zone] = []
        for index in 0...bounds.count {
            let lower: Double? = index > 0 ? bounds[index - 1] : nil
            let upper: Double? = index < bounds.count ? bounds[index] : nil
            switch scale {
            case .proportional:
                zones.append(TrainingZones.Zone(
                    zone: index + 1,
                    minimum: lower.map { (basisValue * $0).rounded() },
                    maximum: upper.map { (basisValue * $0).rounded() }
                ))
            case .inversePace:
                zones.append(TrainingZones.Zone(
                    zone: index + 1,
                    minimum: upper.map { (basisValue / $0).rounded() },
                    maximum: lower.map { (basisValue / $0).rounded() }
                ))
            }
        }
        return TrainingZones(target: target, basis: basis, zones: zones)
    }
}

/// Die Zonen eines Ziels in seiner Einheit (Schläge pro Minute, Watt, Sekunden pro 100 m oder km).
public struct TrainingZones: Codable, Equatable, Sendable {
    public struct Zone: Codable, Equatable, Sendable {
        /// Ab 1.
        public let zone: Int
        /// `nil`: nach unten offen.
        public let minimum: Double?
        /// `nil`: nach oben offen.
        public let maximum: Double?

        public init(zone: Int, minimum: Double?, maximum: Double?) {
            self.zone = zone
            self.minimum = minimum
            self.maximum = maximum
        }
    }

    public let target: StepTarget
    public let basis: PerformanceMetric
    public let zones: [Zone]

    public init(target: StepTarget, basis: PerformanceMetric, zones: [Zone]) {
        self.target = target
        self.basis = basis
        self.zones = zones
    }

    /// `nil` für eine Zone, die es nicht gibt.
    public func zone(_ number: Int) -> Zone? {
        zones.first { $0.zone == number }
    }
}

/// Ein Leistungstest einer Sportart, z. B. der CSS-Test 400/200 m. Wann er im Plan steht, entscheidet der Server
/// (T3), wie er auf der Watch abläuft und ausgewertet wird, das Modul (T5). Hier steht, was er ermittelt.
public struct PerformanceTest: Sendable, Equatable, Identifiable {
    /// Kennung wie bei Sportarten, eindeutig innerhalb der Sportart.
    public let id: String
    public let displayName: String
    /// Die Leistungswerte, die der Test ermittelt.
    public let produces: [PerformanceMetric]
    /// Vollbelastung: Das Ergebnis gilt als getestet und der Test als harte Einheit. Ohne Vollbelastung (Einstiegstest)
    /// bleibt das Ergebnis eine Schätzung.
    public let maximalEffort: Bool
    /// Dauer der eigentlichen Testbelastung ohne Ein- und Auslaufen, in Minuten.
    public let durationMinutes: Int
    /// Was der Athlet nach dem Test einträgt; leer: je ermitteltem Leistungswert ein Feld (`resultInputs`).
    public let inputs: [TestInput]
    public let evaluation: TestEvaluation
    /// Kurzer Hinweis für die Eingabe des Ergebnisses, etwa welcher Abschnitt zählt.
    public let resultHint: String

    public init(
        id: String,
        displayName: String,
        produces: [PerformanceMetric],
        maximalEffort: Bool,
        durationMinutes: Int,
        inputs: [TestInput] = [],
        evaluation: TestEvaluation = .direct,
        resultHint: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.produces = produces
        self.maximalEffort = maximalEffort
        self.durationMinutes = durationMinutes
        self.inputs = inputs
        self.evaluation = evaluation
        self.resultHint = resultHint
    }

    /// Welche Herkunft das Ergebnis bekommt.
    public var resultSource: PerformanceOrigin { maximalEffort ? .tested : .estimated }
}
