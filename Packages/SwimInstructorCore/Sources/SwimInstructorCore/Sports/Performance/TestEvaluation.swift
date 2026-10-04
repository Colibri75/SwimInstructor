import Foundation

/// Ein Wert, den der Athlet nach einem Leistungstest einträgt, etwa die Zeit über 400 m oder den Schnittpuls.
public struct TestInput: Sendable, Equatable, Identifiable {
    /// Bei einer direkten Auswertung die Kennung des Leistungswerts, sonst frei innerhalb des Tests.
    public let id: String
    public let label: String
    /// Einheit wie bei den Leistungswerten: "s" (Zeit, Eingabe als m:ss), "bpm", "W", "s/km" oder "s/100m".
    public let unit: String
    public let range: ClosedRange<Double>
    /// Darf leer bleiben (etwa die Leistung ohne Leistungsmesser).
    public let isOptional: Bool

    public init(id: String, label: String, unit: String, range: ClosedRange<Double>, isOptional: Bool = false) {
        self.id = id
        self.label = label
        self.unit = unit
        self.range = range
        self.isOptional = isOptional
    }
}

/// Wie aus den Eingaben die Leistungswerte eines Tests werden.
public enum TestEvaluation: Sendable, Equatable {
    /// Jede Eingabe ist direkt der Leistungswert mit ihrer Kennung.
    case direct
    /// Critical Swim Speed aus zwei Zeiten (Wakayoshi 1992): Pace pro 100 m = (Zeit lang − Zeit kurz) geteilt durch den
    /// Unterschied der Strecken in 100 m.
    case criticalSwimPace(longInput: String, longMeters: Double, shortInput: String, shortMeters: Double)
    /// Pace pro 100 m aus einer Zeit über eine Strecke.
    case pacePerHundredMeters(input: String, meters: Double)
}

public extension PerformanceTest {
    /// Was der Athlet einträgt. Ohne eigene Eingaben je ermitteltem Leistungswert ein Feld, alle optional (es reicht
    /// einer, etwa nur der Puls ohne Leistungsmesser).
    func resultInputs(definitions: [PerformanceMetricDefinition]) -> [TestInput] {
        guard inputs.isEmpty else { return inputs }
        return produces.compactMap { metric in
            definitions.first { $0.metric == metric }.map {
                TestInput(id: metric.rawValue, label: $0.displayName, unit: $0.unit, range: $0.plausibleRange, isOptional: produces.count > 1)
            }
        }
    }

    /// Die Leistungswerte aus den Eingaben (Kennung → Wert). Fehlt eine nötige Eingabe, liegt sie außerhalb ihres
    /// Bereichs oder ergibt die Rechnung keinen Sinn (lange Strecke nicht langsamer als die kurze), fehlt der Wert.
    func evaluate(_ entries: [String: Double], definitions: [PerformanceMetricDefinition]) -> [PerformanceMetric: Double] {
        let inputs = resultInputs(definitions: definitions)
        var valid: [String: Double] = [:]
        for input in inputs {
            if let value = entries[input.id], value.isFinite, input.range.contains(value) {
                valid[input.id] = value
            }
        }
        switch evaluation {
        case .direct:
            var result: [PerformanceMetric: Double] = [:]
            for metric in produces {
                if let value = valid[metric.rawValue] {
                    result[metric] = value
                }
            }
            return result
        case let .criticalSwimPace(longInput, longMeters, shortInput, shortMeters):
            guard let metric = produces.first, let long = valid[longInput], let short = valid[shortInput],
                  longMeters > shortMeters, long > short else { return [:] }
            return [metric: Self.tenths((long - short) / ((longMeters - shortMeters) / 100))]
        case let .pacePerHundredMeters(input, meters):
            guard let metric = produces.first, let time = valid[input], meters > 0 else { return [:] }
            return [metric: Self.tenths(time / (meters / 100))]
        }
    }

    private static func tenths(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
