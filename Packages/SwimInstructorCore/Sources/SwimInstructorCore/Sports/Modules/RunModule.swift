import Foundation

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
}
