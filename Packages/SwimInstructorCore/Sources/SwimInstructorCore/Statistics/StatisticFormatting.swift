import Foundation

/// Richtung gegenüber dem Zeitraum davor.
public enum StatisticTrend: Equatable, Sendable {
    case up
    case down
    /// Weniger als ein halbes Prozent Unterschied.
    case flat
}

/// Ob die Richtung gut ist: Bei der Pace ist weniger besser, beim Umfang ist keine Richtung besser.
public enum StatisticAssessment: Equatable, Sendable {
    case better
    case worse
    case neutral
}

/// Texte der Kacheln. Im Package, damit sie per Unit-Test prüfbar sind; Zahlen immer mit deutschen Trennzeichen.
public enum StatisticFormatting {
    /// Platzhalter ohne Wert.
    public static let missing = "–"

    /// Nur die Zahl: "12.400", "123,4", "5:30", "5:12", "28,4", "142", "85".
    public static func value(_ value: Double?, format: StatisticFormat) -> String {
        guard let value, value.isFinite else { return missing }
        switch format {
        case .meters, .integer:
            return decimal(value, digits: 0)
        case .kilometers:
            return decimal(value / 1000, digits: 1)
        case .hours:
            let minutes = Int((max(value, 0) / 60).rounded())
            return String(format: "%d:%02d", minutes / 60, minutes % 60)
        case .pace:
            let seconds = Int(max(value, 0).rounded())
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .kilometersPerHour:
            return decimal(value * 3.6, digits: 1)
        case .percent:
            return decimal(value * 100, digits: 0)
        }
    }

    /// Zahl mit Einheit: "5:12 /km", "85 %"; ohne Wert nur der Platzhalter.
    public static func text(_ value: Double?, definition: StatisticDefinition) -> String {
        let number = Self.value(value, format: definition.format)
        guard value?.isFinite == true, !definition.unit.isEmpty else { return number }
        return "\(number) \(definition.unit)"
    }

    public static func sportName(_ sport: SportID?, registry: SportRegistry = .standard) -> String {
        sport.map { registry.displayName(for: $0) } ?? "Alle Sportarten"
    }

    public static func symbolName(_ sport: SportID?, registry: SportRegistry = .standard) -> String {
        sport.map { registry.symbolName(for: $0) } ?? "square.grid.2x2"
    }

    public static func trend(_ result: StatisticResult) -> StatisticTrend? {
        guard let value = result.value, let previous = result.previous, value.isFinite, previous.isFinite else { return nil }
        let scale = max(abs(value), abs(previous))
        guard scale > 0, abs(value - previous) / scale >= 0.005 else { return .flat }
        return value > previous ? .up : .down
    }

    public static func assessment(_ result: StatisticResult) -> StatisticAssessment {
        guard let trend = trend(result), trend != .flat, let higherIsBetter = result.definition.higherIsBetter else { return .neutral }
        return (trend == .up) == higherIsBetter ? .better : .worse
    }

    /// "Vorwoche: 5:20 /km"; `nil` für einen Zeitraum ohne Vergleich.
    public static func comparison(_ result: StatisticResult) -> String? {
        guard let name = result.tile.period.comparisonName else { return nil }
        return "\(name): \(text(result.previous, definition: result.definition))"
    }

    /// Die Zeile unter dem Wert: Anteile je Sportart, worauf der Wert beruht, oder warum es keinen gibt.
    public static func detail(_ result: StatisticResult, registry: SportRegistry = .standard) -> String? {
        if !result.shares.isEmpty {
            return result.shares
                .map { "\(registry.displayName(for: $0.sport)) \(value($0.value, format: result.definition.format))" }
                .joined(separator: " · ")
        }
        guard result.value != nil else { return emptyReason(result.definition.measure) }
        switch result.basis {
        case .workouts(let count)?:
            return count == 1 ? "aus 1 Einheit" : "aus \(count) Einheiten"
        case .days(let count)?:
            return count == 1 ? "an 1 Tag gemessen" : "an \(count) Tagen gemessen"
        case .planDays(let trained, let planned)?:
            return "\(trained) von \(planned) Trainingstagen"
        case nil:
            return nil
        }
    }

    /// Für VoiceOver: "Laufen, Pace pro km, 4 Wochen: 5:12 /km. 4 Wochen davor: 5:20 /km. aus 3 Einheiten"
    public static func accessibilityLabel(_ result: StatisticResult, registry: SportRegistry = .standard) -> String {
        let head = "\(sportName(result.tile.sport, registry: registry)), \(result.definition.displayName), \(result.tile.period.displayName)"
        let parts = ["\(head): \(text(result.value, definition: result.definition))", comparison(result), detail(result, registry: registry)]
        return parts.compactMap { $0 }.joined(separator: ". ")
    }

    private static func emptyReason(_ measure: StatisticMeasure) -> String {
        switch measure {
        case .restingHeartRate, .heartRateVariability, .sleep: return "keine Messung im Zeitraum"
        case .planAdherence: return "kein Plan im Zeitraum"
        default: return "keine passende Einheit im Zeitraum"
        }
    }

    private static func decimal(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        // Ohne das würde aus -0,2 ein "-0".
        let rounded = (value * pow(10, Double(digits))).rounded() / pow(10, Double(digits))
        return formatter.string(from: NSNumber(value: rounded == 0 ? 0 : rounded)) ?? String(rounded)
    }
}
