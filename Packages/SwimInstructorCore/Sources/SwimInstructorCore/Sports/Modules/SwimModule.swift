import Foundation
import HealthKit

public extension SportID {
    static let swim: SportID = "swim"
}

public extension PerformanceMetric {
    /// Critical Swim Speed als Pace in Sekunden pro 100 m: das Tempo, das sich etwa 30 Minuten halten lässt.
    static let criticalSwimPace: PerformanceMetric = "css_pace_per_100m"
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

    public let performanceMetrics: [PerformanceMetricDefinition] = [
        PerformanceMetricDefinition(metric: .criticalSwimPace, displayName: "CSS-Pace", unit: "s/100m", plausibleRange: 50...300)
    ]
    public let performanceTests: [PerformanceTest] = [
        // CSS = 200 m / (Zeit 400 m − Zeit 200 m), beide voll mit Pause dazwischen.
        PerformanceTest(id: "css_400_200", displayName: "CSS-Test 400/200 m", produces: [.criticalSwimPace], maximalEffort: true, durationMinutes: 10),
        // Zeit durch 10 ergibt die Pace pro 100 m, etwas langsamer als die CSS.
        PerformanceTest(id: "time_trial_1000m", displayName: "1000-m-Test", produces: [.criticalSwimPace], maximalEffort: true, durationMinutes: 20)
    ]
    public let zoneSchemes: [ZoneScheme] = [
        // Anteile der CSS-Geschwindigkeit; Zone 4 liegt um die CSS.
        ZoneScheme(target: .pacePerHundredMeters, basis: .criticalSwimPace, scale: .inversePace, bounds: [0.80, 0.88, 0.95, 1.02]),
        // Ohne eigenen Schwellenpuls im Wasser: Anteile des Maximalpulses (im Wasser liegt der Puls niedriger).
        ZoneScheme(target: .heartRateZone, basis: .maxHeartRate, bounds: [0.60, 0.70, 0.80, 0.90])
    ]

    /// CSS ohne Test: die schnellste Durchschnittspace einer Einheit ab 400 m. Pausen am Beckenrand zählen mit,
    /// die Schätzung ist also eher zu langsam als zu schnell.
    public func estimatePerformance(_ context: PerformanceEstimationContext) -> [PerformanceEstimate] {
        let paces = context.workouts.compactMap { workout -> Double? in
            guard let meters = workout.distanceMeters, meters >= 400, workout.duration > 0 else { return nil }
            return workout.duration / meters * 100
        }
        guard let fastest = paces.min() else { return [] }
        return [PerformanceEstimate(metric: .criticalSwimPace, value: fastest.rounded(), source: .estimated)]
    }
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
