import Foundation
import HealthKit

public extension SportID {
    static let rowing: SportID = "rowing"
}

public extension PerformanceMetric {
    /// Zeit für 2000 m in Sekunden, der Standardtest auf dem Ruderergometer.
    static let twoKilometerRowingTime: PerformanceMetric = "time_2000m"
}

/// Rudern, auf dem Ergometer und auf dem Wasser. Intensität nach Schlagzahl, Puls und gefühlter Anstrengung.
public struct RowingModule: SportModule {
    public init() {}

    public let id = SportID.rowing
    public let displayName = "Rudern"
    public let symbolName = "figure.rower"
    public let measures: Set<StepMeasure> = [.duration, .distance]
    public let targets: Set<StepTarget> = [.strokeRate, .heartRateZone, .perceivedEffort]
    // Die Ruderstrecke gibt es in Health erst ab iOS 18; bis dahin zählen Dauer und Puls.
    public let health = SportHealthMapping(activityTypes: [.rowing], distance: nil)
    /// Ganzer Körper ohne Aufprall: etwas weniger als Laufen.
    public let loadFactor = 0.9
    /// 4:10 bis 1:11 pro 500 m.
    public let goalSpeedRange: ClosedRange<Double> = 2...7
    public let planUnit = PlanUnit.minutes
    /// 2:23 pro 500 m.
    public let typicalSpeedMetersPerSecond: Double = 3.5

    public let recording = SportRecording(
        locations: [.indoor, .outdoor],
        primaryField: .speed,
        secondaryFields: [.distanceKilometers],
        speedSmoothing: SpeedSmoothing(window: 20, staleAfter: 10, minimumMeters: 20)
    )

    public let performanceMetrics: [PerformanceMetricDefinition] = [
        .thresholdHeartRate,
        PerformanceMetricDefinition(metric: .twoKilometerRowingTime, displayName: "2000-m-Zeit", unit: "s", plausibleRange: 330...1200)
    ]
    public let performanceTests: [PerformanceTest] = [
        PerformanceTest(
            id: "time_trial_2000m", displayName: "2000-m-Test",
            produces: [.twoKilometerRowingTime, .thresholdHeartRate], maximalEffort: true, durationMinutes: 8,
            resultHint: "Zeit für die 2000 m, Schwellenpuls: Schnitt der letzten 5 Minuten.",
            recorded: [.average(input: PerformanceMetric.thresholdHeartRate.rawValue, signal: .heartRate, lastSeconds: 5 * 60)]
        )
    ]
    public let zoneSchemes: [ZoneScheme] = [
        ZoneScheme(target: .heartRateZone, basis: .thresholdHeartRate, bounds: [0.80, 0.88, 0.94, 1.00])
    ]

    /// Die 2000-m-Zeit ohne Test: die schnellste Einheit ab 2000 m, auf 2000 m umgerechnet.
    public func estimatePerformance(_ context: PerformanceEstimationContext) -> [PerformanceEstimate] {
        let times = context.workouts.compactMap { workout -> Double? in
            guard let meters = workout.distanceMeters, meters >= 2000, workout.duration > 0 else { return nil }
            return workout.duration / meters * 2000
        }
        guard let fastest = times.min() else { return [] }
        return [PerformanceEstimate(metric: .twoKilometerRowingTime, value: fastest.rounded(), source: .estimated)]
    }
}
