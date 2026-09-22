import Foundation
import HealthKit

enum HealthKitAuthorizationError: Error {
    case notAvailableOnDevice
}

/// Abstraction over the authorization call so it can be unit-tested without a real HKHealthStore.
protocol HealthDataAuthorizing {
    func requestAuthorization() async throws
}

@MainActor
final class HealthKitManager: ObservableObject, HealthDataAuthorizing {
    @Published private(set) var isAuthorized = false
    @Published private(set) var lastError: String?

    private let healthStore = HKHealthStore()

    /// All types M2 (data layer) will read: swim workouts plus the vitals the training-state
    /// calculation in M3 needs (heart rate, resting HR, HRV, sleep).
    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    ]

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAuthorizationError.notAvailableOnDevice
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
            // HealthKit never reveals per-type grant/deny status for read access (privacy by
            // design), so "authorized" here only means the request completed without error.
            isAuthorized = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
}
