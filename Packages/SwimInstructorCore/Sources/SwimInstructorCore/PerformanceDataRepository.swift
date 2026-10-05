import Foundation
import HealthKit

/// Was die Schätzung der Leistungswerte über die Einheiten hinaus aus Health braucht.
public protocol PerformanceDataRepository {
    /// Höchster gemessener Puls je Tag ab `startDate`, ein Wert je Tag mit Messung (ohne Reihenfolge).
    func fetchDailyMaximumHeartRates(from startDate: Date) async throws -> [Double]
    /// Alter in Jahren aus dem Geburtsdatum in Health; `nil`, wenn es fehlt oder nicht freigegeben ist.
    func age(now: Date) -> Int?
}

/// Liest die Tageshöchstwerte des Pulses und das Geburtsdatum aus Health. Die Schätzung selbst liegt in `PerformanceEstimator` und den
/// Sport-Modulen und ist dort getestet.
public final class HealthKitPerformanceDataRepository: PerformanceDataRepository {
    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    public func fetchDailyMaximumHeartRates(from startDate: Date) async throws -> [Double] {
        guard let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let end = Date()

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: heartRate,
                quantitySamplePredicate: predicate,
                options: .discreteMax,
                anchorDate: startDate,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    if HealthKitSwimWorkoutRepository.isNoData(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var result: [Double] = []
                collection?.enumerateStatistics(from: startDate, to: end) { statistics, _ in
                    if let value = statistics.maximumQuantity()?.doubleValue(for: unit) {
                        result.append(value)
                    }
                }
                continuation.resume(returning: result)
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
