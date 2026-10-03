import Foundation

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
}
