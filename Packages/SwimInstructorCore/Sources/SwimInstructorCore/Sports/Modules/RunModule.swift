import Foundation
import HealthKit

public extension SportID {
    static let run: SportID = "run"
}

/// Laufen, draußen und auf dem Laufband.
public struct RunModule: SportModule {
    public init() {}

    public let id = SportID.run
    public let displayName = "Laufen"
    public let symbolName = "figure.run"
    public let measures: Set<StepMeasure> = [.distance, .duration]
    public let targets: Set<StepTarget> = [.pacePerKilometer, .heartRateZone, .cadence, .perceivedEffort]
    public let health = SportHealthMapping(
        activityTypes: [.running],
        distance: HealthQuantity(.distanceWalkingRunning, unit: "m", aggregation: .sum),
        metrics: [.averagePower: HealthQuantity(.runningPower, unit: "W", aggregation: .average)]
    )
    public let loadFactor = 1.0
}
