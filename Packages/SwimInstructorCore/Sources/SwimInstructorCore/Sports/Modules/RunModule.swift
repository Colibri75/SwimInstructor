import Foundation
import HealthKit

public extension SportID {
    static let run: SportID = "run"
}

public extension PerformanceMetric {
    /// Schwellentempo in Sekunden pro km: das Tempo, das sich etwa 30 Minuten voll halten lässt.
    static let thresholdPacePerKilometer: PerformanceMetric = "threshold_pace_per_km"
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
    /// 16:40 bis 2:23 pro km.
    public let goalSpeedRange: ClosedRange<Double> = 1...7
    public let planUnit = PlanUnit.minutes
    /// Knapp 6:00 pro km.
    public let typicalSpeedMetersPerSecond: Double = 2.8

    public let recording = SportRecording(
        locations: [.outdoor, .indoor],
        primaryField: .pacePerKilometer,
        secondaryFields: [.distanceKilometers, .power],
        speedSmoothing: SpeedSmoothing(window: 30, staleAfter: 15, minimumMeters: 20)
    )

    public let performanceMetrics: [PerformanceMetricDefinition] = [
        .thresholdHeartRate,
        PerformanceMetricDefinition(metric: .thresholdPacePerKilometer, displayName: "Schwellentempo", unit: "s/km", plausibleRange: 150...900)
    ]
    public let performanceTests: [PerformanceTest] = [
        // Schwellenpuls und -tempo: Schnitt der letzten 20 Minuten. Nur, wenn 30 Minuten Laufen schon vertraut sind.
        PerformanceTest(
            id: "threshold_30min", displayName: "30-Minuten-Test",
            produces: [.thresholdHeartRate, .thresholdPacePerKilometer], maximalEffort: true, durationMinutes: 30,
            resultHint: "Schwellenpuls und Tempo: Schnitt der letzten 20 Minuten.",
            recorded: [
                .average(input: PerformanceMetric.thresholdHeartRate.rawValue, signal: .heartRate, lastSeconds: 20 * 60),
                .average(input: PerformanceMetric.thresholdPacePerKilometer.rawValue, signal: .pacePerKilometer, lastSeconds: 20 * 60)
            ]
        ),
        // Für Einsteiger: locker nach Gefühl, daraus ein geschätztes Schwellentempo.
        PerformanceTest(
            id: "entry_easy_25min", displayName: "Einstiegstest locker",
            produces: [.thresholdPacePerKilometer], maximalEffort: false, durationMinutes: 25,
            resultHint: "Das Tempo schätzt die App aus deinen Läufen; der Test selbst ändert dein Profil nicht."
        )
    ]
    public let zoneSchemes: [ZoneScheme] = [
        // Pulszonen nach Friel in Anteilen des Schwellenpulses.
        ZoneScheme(target: .heartRateZone, basis: .thresholdHeartRate, bounds: [0.85, 0.90, 0.95, 1.00]),
        // Pace-Zonen nach Friel, umgerechnet in Anteile der Schwellengeschwindigkeit.
        ZoneScheme(target: .pacePerKilometer, basis: .thresholdPacePerKilometer, scale: .inversePace, bounds: [0.78, 0.88, 0.94, 1.01])
    ]

    /// Ohne Test: Schwellenpuls 88 % des Maximalpulses (Faustformel), Schwellentempo aus den Läufen mit Puls.
    public func estimatePerformance(_ context: PerformanceEstimationContext) -> [PerformanceEstimate] {
        var estimates: [PerformanceEstimate] = []
        var threshold = context.value(.thresholdHeartRate)
        if let maximum = context.maximumHeartRate {
            let formula = (maximum * 0.88).rounded()
            estimates.append(PerformanceEstimate(metric: .thresholdHeartRate, value: formula, source: .formula))
            threshold = threshold ?? formula
        }
        if let threshold, let resting = context.restingHeartRate,
           let pace = Self.thresholdPace(context.workouts, thresholdHeartRate: threshold, restingHeartRate: resting) {
            estimates.append(PerformanceEstimate(metric: .thresholdPacePerKilometer, value: pace, source: .estimated))
        }
        return estimates
    }

    /// Schwellentempo in s/km aus Läufen mit Puls: Die Geschwindigkeit steigt etwa linear mit dem Puls über Ruhe. Aus
    /// dem Median von Geschwindigkeit durch (Puls − Ruhepuls) folgt die Geschwindigkeit am Schwellenpuls. Braucht
    /// mindestens zwei Läufe ab 2 km und 15 Minuten mit einem Puls mindestens 20 Schläge über Ruhe.
    static func thresholdPace(_ workouts: [Workout], thresholdHeartRate: Double, restingHeartRate: Double) -> Double? {
        let ratios = workouts.compactMap { workout -> Double? in
            guard let meters = workout.distanceMeters, meters >= 2000, workout.duration >= 900,
                  let heartRate = workout.averageHeartRate, heartRate - restingHeartRate >= 20 else { return nil }
            return meters / workout.duration / (heartRate - restingHeartRate)
        }.sorted()
        guard ratios.count >= 2, thresholdHeartRate > restingHeartRate else { return nil }
        let middle = ratios.count / 2
        let median = ratios.count.isMultiple(of: 2) ? (ratios[middle - 1] + ratios[middle]) / 2 : ratios[middle]
        return (1000 / (median * (thresholdHeartRate - restingHeartRate))).rounded()
    }
}
