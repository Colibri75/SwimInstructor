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
    /// 7,2 bis 72 km/h.
    public let goalSpeedRange: ClosedRange<Double> = 2...20
    public let planUnit = PlanUnit.minutes
    /// 25 km/h.
    public let typicalSpeedMetersPerSecond: Double = 7

    public let recording = SportRecording(
        locations: [.outdoor, .indoor],
        primaryField: .speed,
        secondaryFields: [.distanceKilometers, .elevationGain, .power, .cadence],
        speedSmoothing: SpeedSmoothing(window: 15, staleAfter: 10, minimumMeters: 30)
    )

    public let statistics: [StatisticDefinition] = [
        .distanceKilometers, .speed, .duration, .sessions, .averageHeartRate, .averagePower, .averageCadence, .elevationGain,
        .longestDistanceKilometers, .trainingLoad
    ]

    public let performanceMetrics: [PerformanceMetricDefinition] = [.thresholdHeartRate, .thresholdPower]
    public let performanceTests: [PerformanceTest] = [
        // Schwellenpuls: Schnitt der letzten 20 Minuten; FTP: Schnitt der 30 Minuten, nur mit Leistungsmesser.
        PerformanceTest(
            id: "threshold_30min", displayName: "30-Minuten-Test",
            produces: [.thresholdHeartRate, .thresholdPower], maximalEffort: true, durationMinutes: 30,
            resultHint: "Schwellenpuls: Schnitt der letzten 20 Minuten. Leistung: Schnitt der ganzen 30 Minuten, nur mit Leistungsmesser.",
            recorded: [
                .average(input: PerformanceMetric.thresholdHeartRate.rawValue, signal: .heartRate, lastSeconds: 20 * 60),
                .average(input: PerformanceMetric.thresholdPower.rawValue, signal: .power, lastSeconds: nil)
            ]
        )
    ]
    public let zoneSchemes: [ZoneScheme] = [
        // Pulszonen nach Friel in Anteilen des Schwellenpulses.
        ZoneScheme(target: .heartRateZone, basis: .thresholdHeartRate, bounds: [0.81, 0.90, 0.94, 1.00]),
        // Leistungszonen nach Coggan in Anteilen der FTP.
        ZoneScheme(target: .power, basis: .thresholdPower, bounds: [0.55, 0.75, 0.90, 1.05, 1.20])
    ]

    /// Schwellenpuls ohne Test: 85 % des Maximalpulses (Faustformel; auf dem Rad liegt er niedriger als beim Laufen).
    public func estimatePerformance(_ context: PerformanceEstimationContext) -> [PerformanceEstimate] {
        guard let maximum = context.maximumHeartRate else { return [] }
        return [PerformanceEstimate(metric: .thresholdHeartRate, value: (maximum * 0.85).rounded(), source: .formula)]
    }
}
