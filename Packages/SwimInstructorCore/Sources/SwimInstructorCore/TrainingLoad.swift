import Foundation

/// Belastung einer Einheit als eine Zahl, vergleichbar über alle Sportarten, damit der Gesamtplan die Last aus
/// Schwimmen, Rad und Laufen zusammenzählen kann.
///
/// Session-RPE (Foster 2001): Minuten × gefühlte Anstrengung der ganzen Einheit (0 bis 10). Die Anstrengung kommt, in
/// dieser Reihenfolge, aus Health (eigene Bewertung oder Apples Schätzung, `WorkoutMetric.effort`), aus dem Puls
/// (Herzfrequenzreserve, abgeleitet) oder ist `referenceEffort` (mittel). Geteilt durch `referenceEffort`, damit eine
/// Minute mittlerer Anstrengung wie bisher 1 zählt; mal Faktor des Sport-Moduls (Rad belastet pro Minute weniger als
/// Laufen).
public struct TrainingLoadCalculator: Sendable {
    /// Anstrengung, wenn weder Health noch der Puls etwas sagen: etwa "mittel" auf der Skala 0 bis 10.
    public static let referenceEffort = 4.0

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
        return minutes * effort(of: workout) / Self.referenceEffort * factor
    }

    /// Gefühlte Anstrengung der Einheit, 0 bis 10.
    public func effort(of workout: Workout) -> Double {
        if let rated = workout[.effort], rated.isFinite {
            return min(max(rated, 0), 10)
        }
        guard let heartRate = workout.averageHeartRate,
              let resting = restingHeartRate,
              let maximum = maximumHeartRate,
              maximum > resting else {
            return Self.referenceEffort
        }
        let reserve = min(max((heartRate - resting) / (maximum - resting), 0), 1)
        return Self.effort(heartRateReserve: reserve)
    }

    /// Anstrengung aus der mittleren Herzfrequenzreserve (abgeleitet aus Borg CR10 gegen %HFR): 50 % → 3 (locker),
    /// 70 % → 5,4, 90 % → 7,8, höchstens 10, mindestens 1.
    public static func effort(heartRateReserve reserve: Double) -> Double {
        min(max(12 * reserve - 3, 1), 10)
    }

    /// Summe der Belastung je Sportart.
    public func loadBySport(_ workouts: [Workout]) -> [SportID: Double] {
        workouts.reduce(into: [:]) { $0[$1.sport, default: 0] += load(of: $1) }
    }
}
