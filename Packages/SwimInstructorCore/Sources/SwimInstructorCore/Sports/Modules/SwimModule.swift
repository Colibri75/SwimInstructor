import Foundation

public extension SportID {
    static let swim: SportID = "swim"
}

/// Schwimmen, im Becken und im Freiwasser.
public struct SwimModule: SportModule {
    public init() {}

    public let id = SportID.swim
    public let displayName = "Schwimmen"
    public let symbolName = "figure.pool.swim"
    public let measures: Set<StepMeasure> = [.distance, .duration]
    public let targets: Set<StepTarget> = [.pacePerHundredMeters, .heartRateZone, .perceivedEffort]
}
