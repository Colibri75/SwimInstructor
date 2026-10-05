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
    public nonisolated static let readTypes: Set<HKObjectType> = coreReadTypes
        .union(SportRegistry.standard.healthReadTypes)
        .union(HealthKitWorkoutRepository.effortScoreTypes.map { $0 as HKObjectType })

    nonisolated static let coreReadTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
        HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
        HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        // Für den Maximalpuls nach Faustformel, solange es keinen gemessenen gibt.
        HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
    ]

    /// Was die Watch beim Aufzeichnen einer Einheit in Health schreibt: Workout, GPS-Strecke, Puls, Energie und die
    /// Messwerte aller Sportarten (Strecke, Züge, Watt ...). Das iPhone schreibt nichts.
    public nonisolated static let workoutShareTypes: Set<HKSampleType> = SportRegistry.standard.workoutShareTypes

    /// - Parameter shareTypes: zusätzlich zu schreibende Typen; die werden auch gelesen, damit die
    ///   Watch ihre Live-Werte (z. B. Energie) anzeigen darf.
    public init(shareTypes: Set<HKSampleType> = []) {
        self.shareTypes = shareTypes
    }

    /// Läuft gerade eine Anfrage, warten weitere Aufrufer auf genau diese, statt einen zweiten Health-Dialog zu öffnen.
    private var pendingRequest: Task<Void, Error>?

    /// Fragt nur, wenn Health noch etwas zu fragen hat; sonst kommt kein Dialog. Gleichzeitige Aufrufe (Start der Uhr
    /// und Start einer Einheit) teilen sich eine Anfrage, damit der Dialog nicht zweimal hintereinander erscheint.
    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitAuthorizationError.notAvailableOnDevice
        }
        if let pendingRequest {
            return try await pendingRequest.value
        }
        let healthStore = healthStore
        let shareTypes = shareTypes
        let readTypes = Self.readTypes.union(shareTypes.map { $0 as HKObjectType })
        let request = Task {
            let status = try await healthStore.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
            guard status != .unnecessary else { return }
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
        }
        pendingRequest = request
        defer { pendingRequest = nil }
        do {
            try await request.value
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
