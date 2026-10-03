import Foundation
import HealthKit

public enum HealthKitAuthorizationError: Error {
    case notAvailableOnDevice
}

/// Abstraction over the authorization call so it can be unit-tested without a real HKHealthStore.
public protocol HealthDataAuthorizing {
    func requestAuthorization() async throws
}

/// Shared between the iOS app and the watchOS companion app — both request HealthKit access
/// independently, since the Watch is often used without the phone nearby at the pool.
@MainActor
public final class HealthKitManager: ObservableObject, HealthDataAuthorizing {
    @Published public private(set) var isAuthorized = false
    @Published public private(set) var lastError: String?

    private let healthStore = HKHealthStore()
    private let shareTypes: Set<HKSampleType>

    /// All types the app reads: workouts plus the vitals the training-state calculation needs (heart
    /// rate, resting HR, HRV, sleep, energy), plus whatever each sport module reads (distance, strokes,
    /// power, cadence ...).
    // Plain constant data, not tied to actor state - keeping it nonisolated lets callers read it
    // without hopping onto the main actor (and avoids a Swift 6 strict-concurrency error).
    public nonisolated static let readTypes: Set<HKObjectType> = coreReadTypes.union(SportRegistry.standard.healthReadTypes)

    nonisolated static let coreReadTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
        HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    ]

    /// Was die Watch beim Aufzeichnen einer Einheit in Health schreibt (Workout, Strecke, Züge,
    /// Puls, Energie). Das iPhone schreibt nichts.
    public nonisolated static let workoutShareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
        HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    ]

    /// - Parameter shareTypes: zusätzlich zu schreibende Typen; die werden auch gelesen, damit die
    ///   Watch ihre Live-Werte (z. B. Energie) anzeigen darf.
    public init(shareTypes: Set<HKSampleType> = []) {
        self.shareTypes = shareTypes
    }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAuthorizationError.notAvailableOnDevice
        }
        do {
            let readTypes = Self.readTypes.union(shareTypes.map { $0 as HKObjectType })
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
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
