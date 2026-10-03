import Foundation
import HealthKit

public extension SportID {
    static let bike: SportID = "bike"
}

/// Radfahren, draußen und auf der Rolle. Ohne Wattmessung richtet sich die Intensität nach Puls und
/// gefühlter Anstrengung.
public struct BikeModule: SportModule {
    public init() {}

    public let id = SportID.bike
    public let displayName = "Radfahren"
    public let symbolName = "figure.outdoor.cycle"
    public let measures: Set<StepMeasure> = [.duration, .distance]
    public let targets: Set<StepTarget> = [.power, .heartRateZone, .speed, .cadence, .perceivedEffort]
    public let health = SportHealthMapping(
        activityTypes: [.cycling],
        distance: HealthQuantity(.distanceCycling, unit: "m", aggregation: .sum),
        // Watt und Trittfrequenz gibt es in Health erst ab iOS 17 / watchOS 10 (macOS 14), daher als Text.
        metrics: [
            .averagePower: HealthQuantity(identifier: "HKQuantityTypeIdentifierCyclingPower", unit: "W", aggregation: .average),
            .averageCadence: HealthQuantity(identifier: "HKQuantityTypeIdentifierCyclingCadence", unit: "count/min", aggregation: .average)
        ]
    )
    /// Rad belastet bei gleicher Dauer weniger als Laufen (kein Aufprall, Gewicht getragen).
    public let loadFactor = 0.8
}
