import Foundation
import HealthKit

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
    public let health = SportHealthMapping(
        activityTypes: [.swimming],
        distance: HealthQuantity(.distanceSwimming, unit: "m", aggregation: .sum),
        metrics: [.strokes: HealthQuantity(.swimmingStrokeCount, unit: "count", aggregation: .sum)]
    )
    public let loadFactor = 1.0
}

// MARK: - Brücke zum bisherigen Schwimm-Modell

// Die Zustandsberechnung (Pace, Volumen, Snapshot v1) rechnet bis zum Snapshot v2 weiter mit `SwimWorkout`.
// Die Brücke steht hier, weil nur das Schwimm-Modul weiß, welche Werte dazu gehören.

public extension Workout {
    /// Eine Schwimmeinheit im allgemeinen Modell. Ältere Daten ohne Sportart sind immer Schwimmen.
    init(swim workout: SwimWorkout) {
        var metrics: [WorkoutMetric: Double] = [:]
        metrics[.laps] = workout.lapCount.map { Double($0) }
        metrics[.strokes] = workout.totalStrokeCount
        self.init(
            id: workout.id,
            sport: .swim,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            distanceMeters: workout.totalDistanceMeters,
            averageHeartRate: workout.averageHeartRate,
            metrics: metrics
        )
    }
}

public extension SwimWorkout {
    /// `nil` für Einheiten anderer Sportarten.
    init?(workout: Workout) {
        guard workout.sport == .swim else { return nil }
        self.init(
            id: workout.id,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            totalDistanceMeters: workout.distanceMeters,
            lapCount: workout[.laps].map { Int($0.rounded()) },
            totalStrokeCount: workout[.strokes],
            averageHeartRate: workout.averageHeartRate
        )
    }
}
