import Foundation
import HealthKit

/// Ein Pulswert während einer Einheit.
public struct HeartRateSample: Identifiable, Equatable, Sendable {
    public let date: Date
    public let beatsPerMinute: Double

    public var id: Date { date }

    public init(date: Date, beatsPerMinute: Double) {
        self.date = date
        self.beatsPerMinute = beatsPerMinute
    }
}

/// Der Pulsverlauf einer Einheit, für das Diagramm im Detail auf wenige Punkte gemittelt.
public struct HeartRateCurve: Equatable, Sendable {
    /// Ein Punkt: Minuten seit dem Start und mittlerer Puls des Abschnitts.
    public struct Point: Identifiable, Equatable, Sendable {
        public let minute: Double
        public let beatsPerMinute: Double

        public var id: Double { minute }

        public init(minute: Double, beatsPerMinute: Double) {
            self.minute = minute
            self.beatsPerMinute = beatsPerMinute
        }
    }

    public let points: [Point]
    /// Höchster gemessener Einzelwert, nicht der höchste Mittelwert.
    public let maximum: Double?
    public let minimum: Double?

    /// Mittelt die Werte zwischen `start` und `end` auf höchstens `maxPoints` gleich lange Abschnitte; Abschnitte ohne
    /// Messung fallen weg (Pausen, Uhr unter Wasser).
    public init(samples: [HeartRateSample], start: Date, end: Date, maxPoints: Int = 120) {
        let valid = samples.filter { $0.date >= start && $0.date <= end && $0.beatsPerMinute.isFinite && $0.beatsPerMinute > 0 }
        maximum = valid.map(\.beatsPerMinute).max()
        minimum = valid.map(\.beatsPerMinute).min()
        let length = end.timeIntervalSince(start)
        guard length > 0, maxPoints > 0, !valid.isEmpty else {
            points = []
            return
        }
        let bucket = max(length / Double(maxPoints), 1)
        let grouped = Dictionary(grouping: valid) { Int($0.date.timeIntervalSince(start) / bucket) }
        points = grouped.keys.sorted().compactMap { index in
            guard let values = grouped[index], !values.isEmpty else { return nil }
            let mean = values.reduce(0.0) { $0 + $1.beatsPerMinute } / Double(values.count)
            return Point(minute: (Double(index) + 0.5) * bucket / 60, beatsPerMinute: mean)
        }
    }
}

public protocol HeartRateRepository: Sendable {
    /// Alle Pulswerte zwischen `start` und `end`, älteste zuerst.
    func heartRates(from start: Date, to end: Date) async throws -> [HeartRateSample]
}

/// Liest den Puls aus Health. Nach Zeitraum statt nach Workout, damit auch Werte von Geräten zählen, die sie nicht
/// mit dem Workout verknüpfen.
public final class HealthKitHeartRateRepository: HeartRateRepository, @unchecked Sendable {
    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    public func heartRates(from start: Date, to end: Date) async throws -> [HeartRateSample] {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    if HealthKitSwimWorkoutRepository.isNoData(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let values = (samples as? [HKQuantitySample] ?? []).map {
                    HeartRateSample(date: $0.startDate, beatsPerMinute: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }
}
