import Foundation

/// Ein Messwert der Aufzeichnung, aus dem eine Eingabe eines Tests werden kann.
public enum RecordedSignal: Sendable, Equatable {
    case heartRate
    /// Pace in Sekunden pro km aus der Strecke.
    case pacePerKilometer
    case power
}

/// Wie die Watch eine Eingabe eines Tests aus der Aufzeichnung gewinnt.
public enum RecordedMeasurement: Sendable, Equatable {
    /// Die Zeit des Testabschnitts über `meters` Meter wird die Eingabe `input` (Sekunden). Im Becken zählen die Bahnzeiten:
    /// von der ersten Bahn des Tests bis zur Wende nach der letzten, ohne das Warten am Beckenrand davor.
    case segmentTime(input: String, meters: Int)
    /// Mittelwert eines Signals im Testabschnitt nach Zeit, über dessen letzte `lastSeconds` Sekunden (`nil`: den ganzen
    /// Abschnitt). Fehlt das Signal ganz und ist die Eingabe optional, fehlt sie ohne Hinweis (Watt ohne Leistungsmesser).
    case average(input: String, signal: RecordedSignal, lastSeconds: TimeInterval?)

    var input: String {
        switch self {
        case let .segmentTime(input, _): return input
        case let .average(input, _, _): return input
        }
    }
}

/// Was die Watch aus der Aufzeichnung eines Tests gewinnt.
public struct RecordedTestResult: Equatable, Sendable {
    /// Die Eingaben wie beim Eintragen von Hand (`PerformanceProfileLoader.propose`).
    public let entries: [String: Double]
    /// Die Leistungswerte daraus.
    public let values: [PerformanceMetric: Double]
    /// Warum etwas fehlt oder verworfen ist, auf Deutsch.
    public let problems: [String]

    public init(entries: [String: Double], values: [PerformanceMetric: Double], problems: [String]) {
        self.entries = entries
        self.values = values
        self.problems = problems
    }

    /// Mindestens ein Leistungswert ist gültig.
    public var isValid: Bool { !values.isEmpty }
}

public extension PlanStep {
    /// Die eigentliche Testbelastung. Die Module des Servers (`backend/src/sports/modules`) planen sie mit gefühlter
    /// Anstrengung ab 9; Ein- und Auslaufen und Steigerungen liegen darunter.
    var isTestEffort: Bool {
        targetType == .perceivedEffort && (targetValue ?? 0) >= PerformanceTest.testEffort
    }
}

public extension PerformanceTest {
    /// Ab dieser gefühlten Anstrengung ist ein Schritt Testbelastung.
    static let testEffort = 9.0
    /// Längste Lücke in einer Messreihe, die eine Auswertung noch trägt.
    static let maximumGap: TimeInterval = 60
    /// So viel darf ein Testabschnitt nach Zeit kürzer sein, bevor er als abgebrochen gilt.
    static let durationTolerance: TimeInterval = 15
    /// So lange nach dem Ende eines Testabschnitts nach Strecke werden noch Bahnen gesucht: Bahnen, die schon vor dem
    /// Testbeginn liefen, schieben das gemeldete Ende nach vorn.
    static let lapSearchMargin: TimeInterval = 90

    /// Wertet die Aufzeichnung der Watch aus. Ein Test ohne Vollbelastung ändert das Profil nicht und liefert nichts.
    func evaluate(recording: WorkoutRecording, definitions: [PerformanceMetricDefinition]) -> RecordedTestResult {
        guard maximalEffort else {
            return RecordedTestResult(entries: [:], values: [:], problems: [resultHint.isEmpty ? "Dieser Test ändert dein Profil nicht." : resultHint])
        }
        guard !recorded.isEmpty else {
            return RecordedTestResult(entries: [:], values: [:], problems: ["Diesen Test wertet die Watch nicht aus. Trag das Ergebnis auf dem iPhone ein."])
        }
        let inputs = resultInputs(definitions: definitions)
        var entries: [String: Double] = [:]
        var problems: [String] = []
        for measurement in recorded {
            let input = inputs.first { $0.id == measurement.input }
            switch measure(measurement, input: input, recording: recording) {
            case let .value(value):
                entries[measurement.input] = value
            case let .problem(text):
                if !problems.contains(text) { problems.append(text) }
            case .absent:
                break
            }
        }
        for input in inputs {
            guard let value = entries[input.id], !input.range.contains(value) else { continue }
            problems.append("\(input.label) liegt mit \(PlanV2Formatting.performanceValue(value, unit: input.unit)) außerhalb des Plausiblen.")
        }
        let values = evaluate(entries, definitions: definitions)
        if values.isEmpty, problems.isEmpty {
            problems.append("Aus der Aufzeichnung ergibt sich kein gültiger Wert.")
        }
        return RecordedTestResult(entries: entries, values: values, problems: problems)
    }

    private enum Measured {
        case value(Double)
        case problem(String)
        case absent
    }

    private func measure(_ measurement: RecordedMeasurement, input: TestInput?, recording: WorkoutRecording) -> Measured {
        let label = input?.label ?? measurement.input
        switch measurement {
        case let .segmentTime(_, meters):
            return segmentTime(meters: meters, recording: recording)
        case let .average(_, signal, lastSeconds):
            guard let segment = recording.segments.last(where: { $0.unit.step.isTestEffort && $0.unit.plannedSeconds != nil }),
                  let planned = segment.unit.plannedSeconds else {
                return .problem("Der Testabschnitt fehlt in der Aufzeichnung: Die Einheit endete vorher.")
            }
            guard segment.reachedTarget, segment.duration >= planned - Self.durationTolerance else {
                return .problem("Test nach \(PlanFormatting.elapsed(segment.duration)) von \(PlanFormatting.elapsed(planned)) beendet.")
            }
            let end = segment.endElapsed
            let start = lastSeconds.map { max(segment.startElapsed, end - $0) } ?? segment.startElapsed
            return average(signal, from: start, to: end, label: label, isOptional: input?.isOptional ?? false, recording: recording)
        }
    }

    private func segmentTime(meters: Int, recording: WorkoutRecording) -> Measured {
        guard let segment = recording.segments.last(where: { $0.unit.step.isTestEffort && $0.unit.target == .meters(Double(meters)) }) else {
            return .problem("Die \(PlanFormatting.meters(meters)) des Tests fehlen in der Aufzeichnung: Die Einheit endete vorher.")
        }
        guard segment.reachedTarget else {
            return .problem("Test über \(PlanFormatting.meters(meters)) vorzeitig beendet (\(PlanFormatting.meters(Int(segment.meters))) geschafft).")
        }
        return .value((Self.lapTime(of: segment, meters: meters, recording: recording) ?? segment.duration).rounded())
    }

    /// Im Becken die schnellsten aufeinanderfolgenden Bahnen über die Teststrecke rund um den Abschnitt: Bahnen vor dem
    /// Test (Erholen, Warten) oder danach (Ausschwimmen) sind langsamer. `nil` ohne Bahnen oder mit zu wenigen.
    private static func lapTime(of segment: RecordedSegment, meters: Int, recording: WorkoutRecording) -> TimeInterval? {
        guard let lapLength = recording.lapLengthMeters, lapLength > 0, meters % lapLength == 0 else { return nil }
        let count = meters / lapLength
        let candidates = recording.laps.filter {
            $0.end > segment.startElapsed && $0.start < segment.endElapsed + lapSearchMargin
        }
        guard count > 0, candidates.count >= count else { return nil }
        return (0...(candidates.count - count))
            .map { candidates[$0 + count - 1].end - candidates[$0].start }
            .min()
    }

    private func average(
        _ signal: RecordedSignal,
        from start: TimeInterval,
        to end: TimeInterval,
        label: String,
        isOptional: Bool,
        recording: WorkoutRecording
    ) -> Measured {
        switch signal {
        case .heartRate, .power:
            let series = signal == .heartRate ? recording.heartRate : recording.power
            guard let mean = series.mean(from: start, to: end) else {
                return isOptional && signal == .power ? .absent : .problem("\(label): nichts gemessen.")
            }
            let gap = series.longestGap(from: start, to: end)
            guard gap <= Self.maximumGap else {
                return .problem("\(label) verworfen: \(PlanFormatting.elapsed(gap)) ohne Messung.")
            }
            return .value(mean.rounded())
        case .pacePerKilometer:
            guard let first = recording.distance.interpolated(at: start, tolerance: Self.maximumGap),
                  let last = recording.distance.interpolated(at: end, tolerance: Self.maximumGap),
                  last - first > 0 else {
                return .problem("\(label) verworfen: keine Strecke gemessen.")
            }
            return .value(((end - start) / ((last - first) / 1000)).rounded())
        }
    }
}

extension ProgressUnit {
    /// Geplante Dauer bei einer Wiederholung nach Zeit.
    var plannedSeconds: TimeInterval? {
        if case let .seconds(seconds)? = target { return seconds }
        return nil
    }
}
