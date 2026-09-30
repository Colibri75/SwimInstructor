import Foundation

/// Tageswerte der Erholungs-Indikatoren. Jeder Wert ist optional, weil Health nicht jeden Tag
/// alles liefert (z. B. keine HRV-Messung oder keine Schlafaufzeichnung).
public struct DailyVitals: Equatable, Sendable {
    public let date: Date
    public let restingHeartRate: Double?
    public let hrvSDNN: Double?
    public let sleepHours: Double?

    public init(
        date: Date,
        restingHeartRate: Double? = nil,
        hrvSDNN: Double? = nil,
        sleepHours: Double? = nil
    ) {
        self.date = date
        self.restingHeartRate = restingHeartRate
        self.hrvSDNN = hrvSDNN
        self.sleepHours = sleepHours
    }
}
