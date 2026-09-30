import Foundation

/// Werte einer laufenden Schwimmeinheit auf der Watch, unabhängig von HealthKit-Typen.
public struct LiveSwimMetrics: Equatable, Sendable {
    public var elapsed: TimeInterval
    public var distanceMeters: Double
    public var laps: Int
    public var strokes: Double
    public var heartRate: Double?
    public var activeEnergyKilocalories: Double

    public init(
        elapsed: TimeInterval = 0,
        distanceMeters: Double = 0,
        laps: Int = 0,
        strokes: Double = 0,
        heartRate: Double? = nil,
        activeEnergyKilocalories: Double = 0
    ) {
        self.elapsed = elapsed
        self.distanceMeters = distanceMeters
        self.laps = laps
        self.strokes = strokes
        self.heartRate = heartRate
        self.activeEnergyKilocalories = activeEnergyKilocalories
    }

    public static let zero = LiveSwimMetrics()

    /// Schnitt über die ganze Einheit, Pausen am Beckenrand eingerechnet.
    public var averagePaceSecondsPer100m: Double? {
        guard distanceMeters > 0, elapsed > 0 else { return nil }
        return elapsed / (distanceMeters / 100)
    }

    public var strokesPerLap: Double? {
        guard laps > 0, strokes > 0 else { return nil }
        return strokes / Double(laps)
    }

    /// Bahnen aus den Lap-Events der Uhr; kommen die Events später als die Strecke an, zählt die
    /// Strecke geteilt durch die Beckenlänge, damit die Anzeige nicht hinterherhinkt.
    public static func laps(lapEvents: Int, distanceMeters: Double, poolLengthMeters: Int) -> Int {
        guard poolLengthMeters > 0 else { return lapEvents }
        return max(lapEvents, Int((distanceMeters / Double(poolLengthMeters)).rounded(.down)))
    }
}

/// Beckenlänge, die vor dem Start auf der Watch gewählt wird.
public enum PoolLength {
    public static let defaultMeters = 25
    public static let presets = [25, 50]
    /// Was die Uhr als Beckenlänge sinnvoll zählt.
    public static let range = 10...100

    public static func clamped(_ meters: Int) -> Int {
        min(max(meters, range.lowerBound), range.upperBound)
    }
}
