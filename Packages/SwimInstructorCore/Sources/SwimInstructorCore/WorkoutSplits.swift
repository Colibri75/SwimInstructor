import Foundation
import HealthKit

/// Schwimmstil einer Bahn, wie ihn die Apple Watch erkennt (`HKMetadataKeySwimmingStrokeStyle`).
public enum SwimStrokeStyle: Int, Equatable, Sendable {
    case mixed = 1
    case freestyle = 2
    case backstroke = 3
    case breaststroke = 4
    case butterfly = 5
    case kickboard = 6

    public var displayName: String {
        switch self {
        case .mixed: return "Lagen"
        case .freestyle: return "Freistil"
        case .backstroke: return "Rücken"
        case .breaststroke: return "Brust"
        case .butterfly: return "Schmetterling"
        case .kickboard: return "Kickboard"
        }
    }
}

/// Ein Ereignis einer Einheit aus Health, ohne HealthKit-Typen, damit die Auswertung testbar bleibt.
public struct WorkoutEventInterval: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Eine Bahn (Schwimmen) oder eine gedrückte Runde.
        case lap
        /// Ein Abschnitt: beim Schwimmen ein Set, das die Watch an der Pause am Beckenrand erkennt.
        case segment
        case pause
        case resume
    }

    public let kind: Kind
    public let start: Date
    public let end: Date
    public let strokeStyle: SwimStrokeStyle?

    public init(kind: Kind, start: Date, end: Date, strokeStyle: SwimStrokeStyle? = nil) {
        self.kind = kind
        self.start = start
        self.end = end
        self.strokeStyle = strokeStyle
    }
}

/// Eine Messung über einen Zeitraum (Strecke einer Bahn, Züge, Meter zwischen zwei Uhrmessungen).
public struct WorkoutQuantitySample: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let value: Double

    public init(start: Date, end: Date, value: Double) {
        self.start = start
        self.end = end
        self.value = value
    }

    var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
}

/// Was Health zu einer Einheit über ihren Verlauf weiß: Ereignisse, Strecke und Züge als einzelne Messungen.
public struct WorkoutSplitData: Equatable, Sendable {
    public var events: [WorkoutEventInterval]
    public var distance: [WorkoutQuantitySample]
    public var strokes: [WorkoutQuantitySample]
    /// Beckenlänge beim Schwimmen im Becken.
    public var lapLengthMeters: Double?

    public init(
        events: [WorkoutEventInterval] = [],
        distance: [WorkoutQuantitySample] = [],
        strokes: [WorkoutQuantitySample] = [],
        lapLengthMeters: Double? = nil
    ) {
        self.events = events
        self.distance = distance
        self.strokes = strokes
        self.lapLengthMeters = lapLengthMeters
    }
}

/// Ein Teil einer Einheit: eine Bahn, ein Set oder ein Kilometer.
public struct WorkoutSplit: Identifiable, Equatable, Sendable {
    /// Ab 1.
    public let number: Int
    public let start: Date
    public let end: Date
    /// Zeit ohne Pausen.
    public let duration: TimeInterval
    public let distanceMeters: Double?
    public let strokes: Double?
    public let strokeStyle: SwimStrokeStyle?
    public let averageHeartRate: Double?

    public var id: Date { start }

    /// Meter pro Sekunde; `nil` ohne Strecke oder Zeit.
    public var speed: Double? {
        guard let distanceMeters, distanceMeters > 0, duration > 0 else { return nil }
        return distanceMeters / duration
    }

    public init(
        number: Int,
        start: Date,
        end: Date,
        duration: TimeInterval,
        distanceMeters: Double? = nil,
        strokes: Double? = nil,
        strokeStyle: SwimStrokeStyle? = nil,
        averageHeartRate: Double? = nil
    ) {
        self.number = number
        self.start = start
        self.end = end
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.strokes = strokes
        self.strokeStyle = strokeStyle
        self.averageHeartRate = averageHeartRate
    }
}

/// Ein Set mit seinen Bahnen und der Pause davor.
public struct WorkoutSet: Identifiable, Equatable, Sendable {
    public let summary: WorkoutSplit
    public let laps: [WorkoutSplit]
    /// Pause seit dem Ende des vorigen Sets; `nil` beim ersten.
    public let restBefore: TimeInterval?

    public var id: Date { summary.start }

    public init(summary: WorkoutSplit, laps: [WorkoutSplit], restBefore: TimeInterval?) {
        self.summary = summary
        self.laps = laps
        self.restBefore = restBefore
    }
}

/// Sets, Runden und Kilometer einer Einheit, wie Fitness sie zeigt.
public struct WorkoutSplitReport: Equatable, Sendable {
    /// Aus den Abschnitts-Ereignissen: automatische Sets beim Schwimmen, Abschnitte aus der eigenen Watch-App.
    public let sets: [WorkoutSet]
    /// Bahnen oder Runden, die in keinem Set liegen (ohne Sets: alle).
    public let laps: [WorkoutSplit]
    /// Gleich lange Teilstrecken aus der Strecke (Laufen je km, Rad je 5 km).
    public let distanceSplits: [WorkoutSplit]
    /// Länge der Teilstrecken in Metern.
    public let splitLengthMeters: Double?

    public var isEmpty: Bool { sets.isEmpty && laps.isEmpty && distanceSplits.isEmpty }

    public init(sets: [WorkoutSet], laps: [WorkoutSplit], distanceSplits: [WorkoutSplit], splitLengthMeters: Double?) {
        self.sets = sets
        self.laps = laps
        self.distanceSplits = distanceSplits
        self.splitLengthMeters = splitLengthMeters
    }
}

/// Rechnet aus den Health-Daten einer Einheit Sets, Bahnen und Teilstrecken. Messungen zählen zu dem Teil, in dem ihre
/// Mitte liegt: Die Watch schreibt die Strecke beim Schwimmen bahnweise, beim Laufen alle paar Sekunden.
public enum WorkoutSplitBuilder {
    /// Ein Rest unter dieser Strecke wird nicht als eigene Teilstrecke gezeigt.
    static let minimumRemainderMeters = 50.0

    /// Wie lang eine Teilstrecke für das Hauptfeld einer Sportart ist: 1 km beim Laufen, 5 km auf dem Rad. Beim
    /// Schwimmen zeigt Fitness Sets und Bahnen statt Teilstrecken.
    public static func splitLength(for field: LiveField) -> Double? {
        switch field {
        case .pacePerKilometer: return 1000
        case .speed: return 5000
        default: return nil
        }
    }

    public static func report(
        data: WorkoutSplitData,
        heartRates: [HeartRateSample] = [],
        workoutStart: Date,
        workoutEnd: Date,
        splitLengthMeters: Double? = nil
    ) -> WorkoutSplitReport {
        let pauses = pauseIntervals(data.events, workoutEnd: workoutEnd)
        let distance = data.distance.sorted { $0.start < $1.start }
        let context = Context(distance: distance, strokes: data.strokes, heartRates: heartRates, pauses: pauses)

        let lapEvents = data.events.filter { $0.kind == .lap && $0.end > $0.start }.sorted { $0.start < $1.start }
        let segmentEvents = data.events.filter { $0.kind == .segment && $0.end > $0.start }.sorted { $0.start < $1.start }

        // Ohne Streckenmessungen zählt jede Bahn als eine Beckenlänge.
        let fallbackLength = distance.isEmpty ? data.lapLengthMeters : nil
        let allLaps = lapEvents.map { event in
            (event, context.split(number: 0, start: event.start, end: event.end, strokeStyle: event.strokeStyle, fallbackMeters: fallbackLength))
        }

        var sets: [WorkoutSet] = []
        var usedLaps = Set<Date>()
        var previousEnd: Date?
        for (index, segment) in segmentEvents.enumerated() {
            let inside = allLaps.filter { lap in
                let middle = lap.0.start.addingTimeInterval(lap.0.end.timeIntervalSince(lap.0.start) / 2)
                return middle >= segment.start && middle < segment.end
            }
            let laps = inside.enumerated().map { renumber($0.element.1, as: $0.offset + 1) }
            inside.forEach { usedLaps.insert($0.0.start) }
            var summary = context.split(number: index + 1, start: segment.start, end: segment.end, strokeStyle: nil, fallbackMeters: nil)
            if !laps.isEmpty {
                let styles = Set(laps.compactMap(\.strokeStyle))
                let lapMeters = laps.compactMap(\.distanceMeters)
                summary = WorkoutSplit(
                    number: summary.number,
                    start: summary.start,
                    end: summary.end,
                    duration: summary.duration,
                    distanceMeters: summary.distanceMeters ?? (lapMeters.isEmpty ? nil : lapMeters.reduce(0, +)),
                    strokes: summary.strokes,
                    strokeStyle: styles.count == 1 ? styles.first : (styles.isEmpty ? nil : .mixed),
                    averageHeartRate: summary.averageHeartRate
                )
            }
            let rest = previousEnd.map { max(segment.start.timeIntervalSince($0), 0) }
            sets.append(WorkoutSet(summary: summary, laps: laps, restBefore: rest))
            previousEnd = segment.end
        }

        let looseLaps = allLaps
            .filter { !usedLaps.contains($0.0.start) }
            .enumerated()
            .map { renumber($0.element.1, as: $0.offset + 1) }

        var splits: [WorkoutSplit] = []
        if let splitLengthMeters, splitLengthMeters > 0 {
            splits = distanceSplits(distance, length: splitLengthMeters, workoutStart: workoutStart, context: context)
        }

        return WorkoutSplitReport(
            sets: sets,
            laps: looseLaps,
            distanceSplits: splits,
            splitLengthMeters: splits.isEmpty ? nil : splitLengthMeters
        )
    }

    /// Pausen aus Pause/Fortsetzen; eine Pause ohne Fortsetzen geht bis zum Ende.
    static func pauseIntervals(_ events: [WorkoutEventInterval], workoutEnd: Date) -> [DateInterval] {
        var result: [DateInterval] = []
        var pausedAt: Date?
        for event in events.sorted(by: { $0.start < $1.start }) {
            switch event.kind {
            case .pause:
                if pausedAt == nil { pausedAt = event.start }
            case .resume:
                if let start = pausedAt, event.start > start {
                    result.append(DateInterval(start: start, end: event.start))
                }
                pausedAt = nil
            default:
                break
            }
        }
        if let start = pausedAt, workoutEnd > start {
            result.append(DateInterval(start: start, end: workoutEnd))
        }
        return result
    }

    /// Schneidet die Strecke an jeder vollen Teilstrecke; der Zeitpunkt ist linear innerhalb der Messung geschätzt,
    /// in der die Grenze liegt.
    private static func distanceSplits(
        _ samples: [WorkoutQuantitySample],
        length: Double,
        workoutStart: Date,
        context: Context
    ) -> [WorkoutSplit] {
        var result: [WorkoutSplit] = []
        var total = 0.0
        var next = length
        var splitStart = min(workoutStart, samples.first?.start ?? workoutStart)
        var lastEnd = splitStart
        for sample in samples where sample.value > 0 {
            let after = total + sample.value
            while after >= next {
                let fraction = (next - total) / sample.value
                let crossing = sample.start.addingTimeInterval(sample.end.timeIntervalSince(sample.start) * fraction)
                result.append(context.split(number: result.count + 1, start: splitStart, end: crossing, meters: length))
                splitStart = crossing
                next += length
            }
            total = after
            lastEnd = max(lastEnd, sample.end)
        }
        let remainder = total - (next - length)
        if remainder >= minimumRemainderMeters, lastEnd > splitStart {
            result.append(context.split(number: result.count + 1, start: splitStart, end: lastEnd, meters: remainder))
        }
        return result
    }

    private static func renumber(_ split: WorkoutSplit, as number: Int) -> WorkoutSplit {
        WorkoutSplit(
            number: number,
            start: split.start,
            end: split.end,
            duration: split.duration,
            distanceMeters: split.distanceMeters,
            strokes: split.strokes,
            strokeStyle: split.strokeStyle,
            averageHeartRate: split.averageHeartRate
        )
    }

    private struct Context {
        let distance: [WorkoutQuantitySample]
        let strokes: [WorkoutQuantitySample]
        let heartRates: [HeartRateSample]
        let pauses: [DateInterval]

        func split(number: Int, start: Date, end: Date, strokeStyle: SwimStrokeStyle?, fallbackMeters: Double?) -> WorkoutSplit {
            let meters = sum(distance, from: start, to: end)
            return split(
                number: number,
                start: start,
                end: end,
                meters: meters ?? fallbackMeters,
                strokeStyle: strokeStyle
            )
        }

        func split(number: Int, start: Date, end: Date, meters: Double?, strokeStyle: SwimStrokeStyle? = nil) -> WorkoutSplit {
            let pulses = heartRates.filter { $0.date >= start && $0.date < end && $0.beatsPerMinute > 0 }
            let heartRate = pulses.isEmpty ? nil : pulses.reduce(0.0) { $0 + $1.beatsPerMinute } / Double(pulses.count)
            return WorkoutSplit(
                number: number,
                start: start,
                end: end,
                duration: activeDuration(from: start, to: end),
                distanceMeters: meters,
                strokes: sum(strokes, from: start, to: end),
                strokeStyle: strokeStyle,
                averageHeartRate: heartRate
            )
        }

        private func activeDuration(from start: Date, to end: Date) -> TimeInterval {
            let length = end.timeIntervalSince(start)
            guard length > 0 else { return 0 }
            let interval = DateInterval(start: start, end: end)
            let paused = pauses.reduce(0.0) { $0 + ($1.intersection(with: interval)?.duration ?? 0) }
            return max(length - paused, 0)
        }

        private func sum(_ samples: [WorkoutQuantitySample], from start: Date, to end: Date) -> Double? {
            let inside = samples.filter { $0.midpoint >= start && $0.midpoint < end }
            return inside.isEmpty ? nil : inside.reduce(0.0) { $0 + $1.value }
        }
    }
}
