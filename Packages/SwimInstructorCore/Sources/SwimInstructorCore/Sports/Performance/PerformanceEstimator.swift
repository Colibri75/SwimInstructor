import Foundation

/// Ein geschätzter Wert, wie ihn ein Modul liefert; Sportart und Zeitpunkt setzt `PerformanceEstimator`.
public struct PerformanceEstimate: Equatable, Sendable {
    public let metric: PerformanceMetric
    public let value: Double
    /// `.estimated` (aus Messwerten) oder `.formula` (Faustformel).
    public let source: PerformanceOrigin

    public init(metric: PerformanceMetric, value: Double, source: PerformanceOrigin) {
        self.metric = metric
        self.value = value
        self.source = source
    }
}

/// Was ein Modul zum Schätzen bekommt.
public struct PerformanceEstimationContext: Sendable {
    public let sport: SportID
    public let now: Date
    /// Die Einheiten dieser Sportart im Fenster des Snapshots.
    public let workouts: [Workout]
    /// Die schon bekannten Werte: bestätigte aller Sportarten und die für alle Sportarten (Maximal-, Ruhepuls).
    public let known: ResolvedPerformance

    public init(sport: SportID, now: Date, workouts: [Workout], known: ResolvedPerformance) {
        self.sport = sport
        self.now = now
        self.workouts = workouts
        self.known = known
    }

    public var maximumHeartRate: Double? { known.value(.maxHeartRate)?.value }
    public var restingHeartRate: Double? { known.value(.restingHeartRate)?.value }

    /// Ein bekannter Wert dieser Sportart (etwa ein getesteter Schwellenpuls).
    public func value(_ metric: PerformanceMetric) -> Double? {
        known.value(metric, sport: sport)?.value
    }
}

/// Was die Schätzung aus Health bekommt.
public struct PerformanceEstimationInput: Sendable {
    public let now: Date
    /// Die Einheiten aller Sportarten im Fenster des Snapshots.
    public let workouts: [Workout]
    /// Tageswerte; der Ruhepuls ist der Schnitt der letzten sieben Tage mit Messung.
    public let vitals: [DailyVitals]
    /// Höchster gemessener Puls der letzten sechs Monate.
    public let observedMaximumHeartRate: Double?
    /// Alter in Jahren, für die Faustformel des Maximalpulses.
    public let age: Int?

    public init(now: Date, workouts: [Workout], vitals: [DailyVitals], observedMaximumHeartRate: Double?, age: Int?) {
        self.now = now
        self.workouts = workouts
        self.vitals = vitals
        self.observedMaximumHeartRate = observedMaximumHeartRate
        self.age = age
    }
}

/// Startwerte ohne Test: Maximal- und Ruhepuls hier, alles Sportartspezifische im Modul
/// (`SportModule.estimatePerformance`). Bestätigte Werte aus dem Profil gehen immer vor (`ResolvedPerformance`).
public struct PerformanceEstimator: Sendable {
    /// Wie weit der höchste gemessene Puls zurückreicht.
    public static let maximumHeartRateWindowDays = 182

    public let registry: SportRegistry

    public init(registry: SportRegistry = .standard) {
        self.registry = registry
    }

    public func resolve(profile: PerformanceProfile, input: PerformanceEstimationInput) -> ResolvedPerformance {
        var estimates = athleteEstimates(input).map {
            PerformanceValue(metric: $0.metric, value: $0.value, source: $0.source, measuredAt: input.now)
        }
        // Erst die Werte für alle Sportarten auflösen: Die Module rechnen mit dem gültigen Maximalpuls.
        let known = ResolvedPerformance(profile: profile, estimates: estimates, registry: registry)
        for module in registry.modules {
            let context = PerformanceEstimationContext(
                sport: module.id,
                now: input.now,
                workouts: input.workouts.filter { $0.sport == module.id },
                known: known
            )
            estimates += module.estimatePerformance(context).map {
                PerformanceValue(sport: module.id, metric: $0.metric, value: $0.value, source: $0.source, measuredAt: input.now)
            }
        }
        return ResolvedPerformance(profile: profile, estimates: estimates, registry: registry)
    }

    /// Maximalpuls gemessen und nach Tanaka (208 − 0,7 × Alter), Ruhepuls als Schnitt der letzten sieben Messtage.
    func athleteEstimates(_ input: PerformanceEstimationInput) -> [PerformanceEstimate] {
        var estimates: [PerformanceEstimate] = []
        if let observed = input.observedMaximumHeartRate {
            estimates.append(PerformanceEstimate(metric: .maxHeartRate, value: observed.rounded(), source: .estimated))
        }
        if let age = input.age, age > 0 {
            estimates.append(PerformanceEstimate(metric: .maxHeartRate, value: (208 - 0.7 * Double(age)).rounded(), source: .formula))
        }
        let resting = input.vitals
            .filter { $0.restingHeartRate != nil }
            .sorted { $0.date > $1.date }
            .prefix(7)
            .compactMap(\.restingHeartRate)
        if !resting.isEmpty {
            let average = resting.reduce(0, +) / Double(resting.count)
            estimates.append(PerformanceEstimate(metric: .restingHeartRate, value: average.rounded(), source: .estimated))
        }
        return estimates
    }
}
