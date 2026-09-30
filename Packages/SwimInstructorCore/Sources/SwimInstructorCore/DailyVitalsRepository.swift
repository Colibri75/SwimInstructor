import Foundation
import HealthKit

public protocol DailyVitalsRepository {
    /// Tageswerte (Ruhepuls, HRV, Schlaf) ab `startDate` bis jetzt.
    func fetchDailyVitals(from startDate: Date) async throws -> [DailyVitals]
}

/// Liest die Erholungswerte für den Snapshot aus Health. Die Umrechnung selbst (Schlaf pro Nacht,
/// Zusammenführen pro Tag) liegt in `DailyVitalsAggregator` und ist dort getestet.
public final class HealthKitDailyVitalsRepository: DailyVitalsRepository {
    private let healthStore: HKHealthStore
    private let calendar: Calendar

    public init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
        self.healthStore = healthStore
        self.calendar = calendar
    }

    public func fetchDailyVitals(from startDate: Date) async throws -> [DailyVitals] {
        let start = calendar.startOfDay(for: startDate)
        async let resting = dailyAverages(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            from: start
        )
        async let hrv = dailyAverages(
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            from: start
        )
        // Die Nacht auf den ersten Tag beginnt am Abend davor.
        async let sleep = sleepIntervals(from: start.addingTimeInterval(-12 * 3600))

        let aggregator = DailyVitalsAggregator(calendar: calendar)
        let sleepHours = try await aggregator.sleepHoursPerDay(sleep).filter { $0.key >= start }
        return try await aggregator.assemble(restingHeartRate: resting, hrvSDNN: hrv, sleepHours: sleepHours)
    }

    // MARK: - Intern

    /// Tagesmittel einer Größe. Tage ohne Messung fehlen im Ergebnis.
    private func dailyAverages(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from start: Date
    ) async throws -> [Date: Double] {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        let end = Date()

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    if HealthKitSwimWorkoutRepository.isNoData(error) {
                        continuation.resume(returning: [:])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var result: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let value = statistics.averageQuantity()?.doubleValue(for: unit) {
                        result[statistics.startDate] = value
                    }
                }
                continuation.resume(returning: result)
            }
            healthStore.execute(query)
        }
    }

    /// Nur Abschnitte, in denen geschlafen wurde (Kern, Tief, REM, unbestimmt), nicht "im Bett".
    private func sleepIntervals(from start: Date) async throws -> [SleepInterval] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    if HealthKitSwimWorkoutRepository.isNoData(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues
        return samples
            .filter { sample in HKCategoryValueSleepAnalysis(rawValue: sample.value).map { asleep.contains($0) } ?? false }
            .map { SleepInterval(start: $0.startDate, end: $0.endDate) }
    }
}
