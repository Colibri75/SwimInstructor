import Foundation
import HealthKit

public protocol SwimWorkoutRepository {
    func fetchRecentSwimWorkouts(limit: Int) async throws -> [SwimWorkout]
}

/// Reads swim workouts plus the vitals/lap data attached to them. Fetching (this type) is kept
/// separate from mapping (`map`, `lapCount`) so the transformation logic stays unit-testable
/// without a real HealthKit store.
public final class HealthKitSwimWorkoutRepository: SwimWorkoutRepository {
    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    public func fetchRecentSwimWorkouts(limit: Int = 50) async throws -> [SwimWorkout] {
        let workouts = try await queryWorkouts(limit: limit)

        var result: [SwimWorkout] = []
        for workout in workouts {
            let distance = try await sumQuantity(identifier: .distanceSwimming, unit: .meter(), workout: workout)
            let strokes = try await sumQuantity(identifier: .swimmingStrokeCount, unit: .count(), workout: workout)
            let heartRate = try await averageHeartRate(for: workout)

            result.append(
                Self.map(
                    workout: workout,
                    distanceMeters: distance,
                    totalStrokeCount: strokes,
                    averageHeartRate: heartRate
                )
            )
        }
        return result
    }

    static func map(
        workout: HKWorkout,
        distanceMeters: Double?,
        totalStrokeCount: Double?,
        averageHeartRate: Double?
    ) -> SwimWorkout {
        SwimWorkout(
            id: workout.uuid,
            startDate: workout.startDate,
            endDate: workout.endDate,
            duration: workout.duration,
            totalDistanceMeters: distanceMeters,
            lapCount: lapCount(from: workout),
            totalStrokeCount: totalStrokeCount,
            averageHeartRate: averageHeartRate
        )
    }

    static func lapCount(from workout: HKWorkout) -> Int? {
        guard let events = workout.workoutEvents else { return nil }
        let laps = events.filter { $0.type == .lap }.count
        return laps > 0 ? laps : nil
    }

    private func queryWorkouts(limit: Int) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForWorkouts(with: .swimming)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: limit,
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

    private func sumQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        workout: HKWorkout
    ) async throws -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func averageHeartRate(for workout: HKWorkout) async throws -> Double? {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
}
