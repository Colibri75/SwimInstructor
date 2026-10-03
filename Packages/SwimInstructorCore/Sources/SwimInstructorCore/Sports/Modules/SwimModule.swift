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
    /// 10:00 bis 0:40 pro 100 m.
    public let goalSpeedRange: ClosedRange<Double> = 0.15...2.5
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

// MARK: - Brücke zum bisherigen Schwimmziel

public extension TrainingGoal {
    /// Das bisherige Schwimmziel als Gesamtziel: eine Disziplin, Schwerpunkt 100 % Schwimmen. Trainingstage und
    /// Stunden kannte das alte Ziel nicht; 4 Tage und 4 Stunden passen zu dem, was der Plan bisher vorsah.
    init(legacy goal: AthleteGoal) {
        self.init(
            template: goal.distanceMeters == 3_800 ? "swim_long" : nil,
            disciplines: [Discipline(sport: .swim, distanceMeters: goal.distanceMeters, targetDurationSeconds: goal.targetDurationSeconds)],
            targetDate: goal.targetDate,
            trainingDaysPerWeek: 4,
            weeklyHours: 4,
            emphasis: [Emphasis(sport: .swim, percent: 100)]
        )
    }

    /// 3,8 km Schwimmen in unter 60 Minuten bis zum 04.07.2027, wie `AthleteGoal.default`.
    static let `default` = TrainingGoal(legacy: .default)

    /// Bis die Planung alle Sportarten kann (T3), plant der Server nur Schwimmen und braucht dafür ein Schwimmziel
    /// (`goal` im Snapshot). Das ist die Schwimm-Disziplin; ohne Zielzeit gilt 2:00 pro 100 m. Ohne Schwimm-Disziplin
    /// steht dort ein Platzhalter (1500 m in 45 Minuten), den der Server laut v2-Abschnitt nur als Ausgleich nimmt.
    var legacySwimGoal: AthleteGoal {
        guard let swim = discipline(for: .swim) else {
            return AthleteGoal(distanceMeters: 1_500, targetDurationSeconds: 2_700, targetDate: targetDate)
        }
        return AthleteGoal(
            distanceMeters: swim.distanceMeters,
            targetDurationSeconds: swim.targetDurationSeconds ?? swim.distanceMeters / 100 * 120,
            targetDate: targetDate
        )
    }
}
