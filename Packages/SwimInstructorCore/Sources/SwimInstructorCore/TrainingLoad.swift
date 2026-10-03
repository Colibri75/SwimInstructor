import Foundation

/// Belastung einer Einheit als eine Zahl, vergleichbar über alle Sportarten, damit der Gesamtplan die Last aus
/// Schwimmen, Rad und Laufen zusammenzählen kann.
///
/// Mit Ruhe- und Maximalpuls: Banisters TRIMP (Minuten × Herzfrequenzreserve × 0,64 · e^(1,92 · Reserve)).
/// Ohne Puls: Minuten × 1,0, das entspricht etwa einer lockeren bis mittleren Einheit nach TRIMP. In beiden
/// Fällen zählt der Faktor des Sport-Moduls mit (Rad belastet pro Minute weniger als Laufen).
public struct TrainingLoadCalculator: Sendable {
    public let registry: SportRegistry
    public let restingHeartRate: Double?
    public let maximumHeartRate: Double?

    public init(registry: SportRegistry = .standard, restingHeartRate: Double? = nil, maximumHeartRate: Double? = nil) {
        self.registry = registry
        self.restingHeartRate = restingHeartRate
        self.maximumHeartRate = maximumHeartRate
    }

    public func load(of workout: Workout) -> Double {
        let minutes = max(0, workout.duration) / 60
        // Unbekannte Sportart (neuere App-Version, ältere Registry): wie Laufen zählen statt zu ignorieren.
        let factor = registry.module(for: workout.sport)?.loadFactor ?? 1
        guard let heartRate = workout.averageHeartRate,
              let resting = restingHeartRate,
              let maximum = maximumHeartRate,
              maximum > resting else {
            return minutes * factor
        }
        let reserve = min(max((heartRate - resting) / (maximum - resting), 0), 1)
        return minutes * reserve * 0.64 * exp(1.92 * reserve) * factor
    }

    /// Summe der Belastung je Sportart.
    public func loadBySport(_ workouts: [Workout]) -> [SportID: Double] {
        workouts.reduce(into: [:]) { $0[$1.sport, default: 0] += load(of: $1) }
    }
}
