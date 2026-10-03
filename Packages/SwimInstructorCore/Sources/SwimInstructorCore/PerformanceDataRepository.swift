import Foundation
import HealthKit

/// Was die Schätzung der Leistungswerte über die Einheiten hinaus aus Health braucht.
public protocol PerformanceDataRepository {
    /// Höchster gemessener Puls ab `startDate`; `nil` ohne Messung.
    func fetchMaximumHeartRate(from startDate: Date) async throws -> Double?
    /// Alter in Jahren aus dem Geburtsdatum in Health; `nil`, wenn es fehlt oder nicht freigegeben ist.
    func age(now: Date) -> Int?
}

/// Liest höchsten Puls und Geburtsdatum aus Health. Die Schätzung selbst liegt in `PerformanceEstimator` und den
/// Sport-Modulen und ist dort getestet.
public final class HealthKitPerformanceDataRepository: PerformanceDataRepository {
    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    public func fetchMaximumHeartRate(from startDate: Date) async throws -> Double? {
        guard let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: heartRate, quantitySamplePredicate: predicate, options: .discreteMax) { _, statistics, error in
                if let error {
                    if HealthKitSwimWorkoutRepository.isNoData(error) {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: statistics?.maximumQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    public func age(now: Date) -> Int? {
        let calendar = Calendar(identifier: .gregorian)
        guard let components = try? healthStore.dateOfBirthComponents(),
              let birthday = calendar.date(from: components) else { return nil }
        return calendar.dateComponents([.year], from: birthday, to: now).year
    }
}
