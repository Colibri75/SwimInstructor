import Foundation
import HealthKit

public protocol WorkoutRepository {
    /// Alle Einheiten der angemeldeten Sportarten ab `startDate`, neueste zuerst.
    func fetchWorkouts(from startDate: Date) async throws -> [Workout]
}

/// Liest die Einheiten aller Sportarten der Registry aus Health. Welche Workout-Arten und Messwerte dazu gehören,
/// sagt das jeweilige Modul; dieser Typ kennt keine Sportart selbst. Wie beim Schwimm-Repository ist das Lesen
/// (hier) vom Umwandeln (`map`) getrennt, damit die Umwandlung ohne echten Health-Speicher testbar bleibt.
public final class HealthKitWorkoutRepository: WorkoutRepository {
    /// Werte, die jedes Workout haben kann, egal welche Sportart.
    static let heartRate = HealthQuantity(.heartRate, unit: "count/min", aggregation: .average)
    static let activeEnergy = HealthQuantity(.activeEnergyBurned, unit: "kcal", aggregation: .sum)

    private let healthStore: HKHealthStore
    private let registry: SportRegistry

    public init(healthStore: HKHealthStore = HKHealthStore(), registry: SportRegistry = .standard) {
        self.healthStore = healthStore
        self.registry = registry
    }

    public func fetchWorkouts(from startDate: Date) async throws -> [Workout] {
        let activityTypes = registry.activityTypes
        guard !activityTypes.isEmpty else { return [] }

        var result: [Workout] = []
        for workout in try await queryWorkouts(activityTypes: activityTypes, startDate: startDate) {
            guard let module = registry.module(forActivityType: workout.workoutActivityType) else { continue }
            var distance: Double?
            if let quantity = module.health.distance {
                distance = try await statistic(quantity, for: workout)
            }
            var metrics: [WorkoutMetric: Double] = [:]
            for (metric, quantity) in module.health.metrics {
                metrics[metric] = try await statistic(quantity, for: workout)
            }
            let heartRate = try await statistic(Self.heartRate, for: workout)
            let energy = try await statistic(Self.activeEnergy, for: workout)
            result.append(
                Self.map(
                    workout: workout,
                    sport: module.id,
                    distanceMeters: distance,
                    averageHeartRate: heartRate,
                    activeEnergyKilocalories: energy,
                    metrics: metrics
                )
            )
        }
        return result
    }

    /// Ergänzt die gelesenen Werte um das, was im Workout selbst steht (Runden, Höhenmeter).
    static func map(
        workout: HKWorkout,
        sport: SportID,
        distanceMeters: Double?,
        averageHeartRate: Double?,
        activeEnergyKilocalories: Double?,
        metrics: [WorkoutMetric: Double]
    ) -> Workout {
        var allMetrics = metrics
        if let laps = HealthKitSwimWorkoutRepository.lapCount(from: workout) {
            allMetrics[.laps] = Double(laps)
        }
        if let elevation = elevationGain(from: workout) {
            allMetrics[.elevationGain] = elevation
        }
        return Workout(
            id: workout.uuid,
            sport: sport,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            distanceMeters: distanceMeters,
            averageHeartRate: averageHeartRate,
            activeEnergyKilocalories: activeEnergyKilocalories,
            metrics: allMetrics
        )
    }

    static func elevationGain(from workout: HKWorkout) -> Double? {
        guard let quantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity,
              quantity.is(compatibleWith: .meter()) else { return nil }
        return quantity.doubleValue(for: .meter())
    }

    private func queryWorkouts(activityTypes: [HKWorkoutActivityType], startDate: Date) async throws -> [HKWorkout] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: activityTypes.map { HKQuery.predicateForWorkouts(with: $0) }),
            HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        ])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    /// Summe oder Mittelwert eines Messwerts über die Einheit; `nil`, wenn es keine Messung gibt oder das System
    /// den Typ nicht kennt.
    private func statistic(_ quantity: HealthQuantity, for workout: HKWorkout) async throws -> Double? {
        guard let quantityType = quantity.quantityType else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let unit = quantity.healthUnit
        let isSum = quantity.aggregation == .sum

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: isSum ? .cumulativeSum : .discreteAverage
            ) { _, statistics, error in
                if let error {
                    if HealthKitSwimWorkoutRepository.isNoData(error) {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let value = isSum ? statistics?.sumQuantity() : statistics?.averageQuantity()
                continuation.resume(returning: value?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
}
