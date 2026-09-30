import Foundation

/// Ein Schlafabschnitt, wie ihn Health liefert (nur die Phasen, in denen tatsächlich geschlafen
/// wurde; "im Bett" und "wach" filtert der Aufrufer vorher heraus).
public struct SleepInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// Reine Umrechnung von Health-Rohwerten in `DailyVitals`, ohne HealthKit, damit sie ohne Gerät
/// testbar bleibt. Der HealthKit-Teil steht in `HealthKitDailyVitalsRepository`.
public struct DailyVitalsAggregator {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Schlafstunden pro Nacht. Eine Nacht zählt zu dem Tag, an dem sie endet (Aufwachtag), damit
    /// die Nacht auf heute als "heute" in die Erholung eingeht.
    ///
    /// Schreiben mehrere Quellen dieselbe Nacht (Watch und iPhone, Kern- und Tiefschlaf als
    /// getrennte Abschnitte), überlappen sich die Abschnitte. Sie werden vorher zusammengeführt,
    /// sonst zählt dieselbe Stunde doppelt.
    public func sleepHoursPerDay(_ intervals: [SleepInterval]) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for interval in merged(intervals) {
            let day = calendar.startOfDay(for: interval.end)
            result[day, default: 0] += interval.end.timeIntervalSince(interval.start) / 3600
        }
        return result
    }

    /// Führt die Tageswerte zu `DailyVitals` zusammen, ein Eintrag pro Tag mit mindestens einem
    /// Wert, nach Datum sortiert. Die Schlüssel werden auf den Tagesanfang normalisiert.
    public func assemble(
        restingHeartRate: [Date: Double],
        hrvSDNN: [Date: Double],
        sleepHours: [Date: Double]
    ) -> [DailyVitals] {
        let resting = normalized(restingHeartRate)
        let hrv = normalized(hrvSDNN)
        let sleep = normalized(sleepHours)
        let days = Set(resting.keys).union(hrv.keys).union(sleep.keys)

        return days.sorted().map { day in
            DailyVitals(
                date: day,
                restingHeartRate: resting[day],
                hrvSDNN: hrv[day],
                sleepHours: sleep[day]
            )
        }
    }

    // MARK: - Intern

    private func merged(_ intervals: [SleepInterval]) -> [SleepInterval] {
        var result: [SleepInterval] = []
        for interval in intervals.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = SleepInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    /// Bei mehreren Werten für denselben Tag gewinnt der Mittelwert.
    private func normalized(_ values: [Date: Double]) -> [Date: Double] {
        var grouped: [Date: [Double]] = [:]
        for (date, value) in values {
            grouped[calendar.startOfDay(for: date), default: []].append(value)
        }
        return grouped.mapValues { $0.reduce(0, +) / Double($0.count) }
    }
}
