import Foundation

/// Woran ein Schritt einer Einheit gemessen wird. Jede Sportart nennt in ihrem Modul, welche Maße sie
/// versteht. Die Raw-Werte sind Teil des Vertrags mit dem Server (`contracts/sports.json`).
public enum StepMeasure: String, Codable, Sendable, CaseIterable {
    /// Strecke in Metern (z. B. 6 × 200 m Schwimmen, 5 × 1 km Laufen).
    case distance
    /// Dauer in Sekunden (z. B. 6 × 3 min Laufen, 2 h Rad).
    case duration
    /// Wiederholungen ohne Strecke oder Zeit (z. B. Krafttraining).
    case repetitions
}

/// Woran sich die Intensität eines Schritts ausrichtet. Raw-Werte sind Teil des Vertrags mit dem Server.
public enum StepTarget: String, Codable, Sendable, CaseIterable {
    case pacePerHundredMeters = "pace_per_100m"
    case pacePerKilometer = "pace_per_km"
    case speed
    case heartRateZone = "heart_rate_zone"
    case power
    case cadence
    case strokeRate = "stroke_rate"
    case perceivedEffort = "perceived_effort"
}

/// In welcher Einheit der Plan den Umfang einer Sportart führt (`amount` in Plan v2): Meter beim Schwimmen, Minuten
/// bei Rad und Laufen. Die Raw-Werte sind Teil des Vertrags mit dem Server (`contracts/sports.json`).
public enum PlanUnit: String, Codable, Sendable, CaseIterable {
    case meters
    case minutes
}
