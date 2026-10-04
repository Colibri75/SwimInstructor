import Foundation

/// Ein Messwert zu einer Laufzeit (Sekunden ohne Pausen der Aufzeichnung).
public struct TimedValue: Codable, Equatable, Sendable {
    public let elapsed: TimeInterval
    public let value: Double

    public init(elapsed: TimeInterval, value: Double) {
        self.elapsed = elapsed
        self.value = value
    }
}

/// Eine Bahn im Becken, von der Wende davor bis zur Wende danach, in Laufzeit.
public struct LapTime: Codable, Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

/// Was die Uhr während einer Einheit mitschreibt: Messreihen nach Laufzeit und die Abschnitte aus `SessionProgress`.
/// Grundlage der Auswertung von Leistungstests (`PerformanceTest.evaluate(recording:definitions:)`).
///
/// Puls und Leistung stehen mit der Zeit ihrer Messung, nicht der ihres Eintreffens: Fehlt der Sensor eine Weile, zeigt
/// die Reihe eine Lücke, statt den letzten Wert zu wiederholen.
public struct WorkoutRecording: Equatable, Sendable {
    /// Höchstens so viele Werte je Reihe (gut fünf Stunden bei einem Wert pro Sekunde).
    public static let sampleLimit = 20_000

    /// Bahnlänge im Becken, sonst `nil`.
    public var lapLengthMeters: Int?
    public private(set) var heartRate: [TimedValue]
    /// Strecke seit dem Start in Metern; nur steigende Werte.
    public private(set) var distance: [TimedValue]
    public private(set) var power: [TimedValue]
    public private(set) var laps: [LapTime]
    /// Die beendeten Wiederholungen aus `SessionProgress.segments`.
    public var segments: [RecordedSegment]

    public init(
        lapLengthMeters: Int? = nil,
        heartRate: [TimedValue] = [],
        distance: [TimedValue] = [],
        power: [TimedValue] = [],
        laps: [LapTime] = [],
        segments: [RecordedSegment] = []
    ) {
        self.lapLengthMeters = lapLengthMeters
        self.heartRate = heartRate
        self.distance = distance
        self.power = power
        self.laps = laps
        self.segments = segments
    }

    public mutating func recordHeartRate(_ beatsPerMinute: Double, at elapsed: TimeInterval) {
        Self.append(&heartRate, TimedValue(elapsed: elapsed, value: beatsPerMinute))
    }

    public mutating func recordPower(_ watts: Double, at elapsed: TimeInterval) {
        Self.append(&power, TimedValue(elapsed: elapsed, value: watts))
    }

    /// Nur ein Zuwachs zählt: Steht der Athlet, bleibt die Reihe stehen.
    public mutating func recordDistance(_ meters: Double, at elapsed: TimeInterval) {
        if let last = distance.last, meters <= last.value { return }
        Self.append(&distance, TimedValue(elapsed: elapsed, value: meters))
    }

    /// Eine Bahn; eine schon bekannte oder ältere zählt nicht noch einmal.
    public mutating func recordLap(start: TimeInterval, end: TimeInterval) {
        guard start.isFinite, end.isFinite, end >= start, laps.count < Self.sampleLimit else { return }
        if let last = laps.last, end <= last.end { return }
        laps.append(LapTime(start: start, end: end))
    }

    /// Hält die Reihe nach der Zeit sortiert; derselbe Zeitpunkt ersetzt den Wert.
    private static func append(_ series: inout [TimedValue], _ sample: TimedValue) {
        guard sample.value.isFinite, sample.elapsed.isFinite, sample.elapsed >= 0 else { return }
        if let last = series.last {
            guard sample.elapsed >= last.elapsed else { return }
            if sample.elapsed == last.elapsed {
                series[series.count - 1] = sample
                return
            }
        }
        guard series.count < sampleLimit else { return }
        series.append(sample)
    }
}

// MARK: - Auswertung der Reihen

public extension Array where Element == TimedValue {
    /// Die Werte zwischen `start` und `end` (beide eingeschlossen).
    func values(from start: TimeInterval, to end: TimeInterval) -> [TimedValue] {
        filter { $0.elapsed >= start && $0.elapsed <= end }
    }

    /// Die längste Strecke ohne Messung zwischen `start` und `end`, Ränder eingerechnet. Ohne Messung das ganze Fenster.
    func longestGap(from start: TimeInterval, to end: TimeInterval) -> TimeInterval {
        let times = values(from: start, to: end).map(\.elapsed)
        guard let first = times.first, let last = times.last else { return Swift.max(end - start, 0) }
        var gap = Swift.max(first - start, end - last)
        for (earlier, later) in zip(times, times.dropFirst()) {
            gap = Swift.max(gap, later - earlier)
        }
        return gap
    }

    /// Mittelwert der Werte zwischen `start` und `end`, `nil` ohne Werte.
    func mean(from start: TimeInterval, to end: TimeInterval) -> Double? {
        let window = values(from: start, to: end)
        guard !window.isEmpty else { return nil }
        return window.reduce(0) { $0 + $1.value } / Double(window.count)
    }

    /// Der Wert zur Zeit `elapsed`, linear zwischen den Nachbarn. `nil`, wenn kein Wert näher als `tolerance` davor und
    /// danach liegt (am Rand reicht ein Wert in dieser Nähe).
    func interpolated(at elapsed: TimeInterval, tolerance: TimeInterval) -> Double? {
        let before = last { $0.elapsed <= elapsed }
        let after = first { $0.elapsed >= elapsed }
        switch (before, after) {
        case let (before?, after?):
            guard after.elapsed > before.elapsed else { return before.value }
            guard elapsed - before.elapsed <= tolerance || after.elapsed - elapsed <= tolerance else { return nil }
            let share = (elapsed - before.elapsed) / (after.elapsed - before.elapsed)
            return before.value + (after.value - before.value) * share
        case let (before?, nil):
            return elapsed - before.elapsed <= tolerance ? before.value : nil
        case let (nil, after?):
            return after.elapsed - elapsed <= tolerance ? after.value : nil
        case (nil, nil):
            return nil
        }
    }
}
