import Foundation

/// Texte für die Anzeige von Plan v2. Im Package, damit iPhone und Watch dieselben Formulierungen nutzen und sie per
/// Unit-Test prüfbar sind.
public enum PlanV2Formatting {
    /// Umfang in der Einheit der Sportart: "1.500 m" bzw. "58 min" oder "2:15 h".
    public static func amount(_ amount: Double, unit: PlanUnit) -> String {
        switch unit {
        case .meters: return PlanFormatting.distance(amount)
        case .minutes: return duration(minutes: amount)
        }
    }

    /// Bis 119 Minuten in Minuten ("90 min"), darüber in Stunden ("2:15 h").
    public static func duration(minutes: Double) -> String {
        let total = max(Int(minutes.rounded()), 0)
        guard total >= 120 else { return "\(total) min" }
        return String(format: "%d:%02d h", total / 60, total % 60)
    }

    /// 45 → "45 s", 60 → "1 min", 90 → "1:30 min".
    public static func duration(seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) s" }
        guard seconds % 60 != 0 else { return "\(seconds / 60) min" }
        return String(format: "%d:%02d min", seconds / 60, seconds % 60)
    }

    /// Kurzform der Einheit für Eingabefelder: "m" oder "min".
    public static func unitSymbol(_ unit: PlanUnit) -> String {
        switch unit {
        case .meters: return "m"
        case .minutes: return "min"
        }
    }

    /// "Schwimmen · 1.500 m", auch für Sportarten, die diese App-Version nicht kennt.
    public static func sessionTitle(sport: SportID, amount: Double, unit: PlanUnit, registry: SportRegistry = .standard) -> String {
        "\(registry.displayName(for: sport)) · \(self.amount(amount, unit: unit))"
    }

    /// Umfang eines Schritts: "4 × 50 m", "3 × 1 min", "30 min".
    public static func stepVolume(_ step: PlanStep) -> String {
        let single: String
        if step.measure == .duration, let seconds = step.durationSeconds {
            single = duration(seconds: seconds)
        } else if let meters = step.distanceMeters {
            single = PlanFormatting.meters(meters)
        } else if let seconds = step.durationSeconds {
            single = duration(seconds: seconds)
        } else {
            single = ""
        }
        guard step.repetitions > 1 else { return single }
        return single.isEmpty ? "\(step.repetitions) ×" : "\(step.repetitions) × \(single)"
    }

    /// Das Ziel eines Schritts: "2:05 /100 m", "5:30 /km", "Zone 2", "220 W", "28 km/h", "90 /min", "Anstrengung 6 von 10".
    public static func target(_ step: PlanStep) -> String? {
        guard let type = step.targetType, let value = step.targetValue else { return nil }
        switch type {
        case .pacePerHundredMeters: return "\(PlanFormatting.pace(value)) /100 m"
        case .pacePerKilometer: return "\(PlanFormatting.pace(value)) /km"
        case .heartRateZone: return "Zone \(Int(value.rounded()))"
        case .power: return "\(Int(value.rounded())) W"
        case .speed: return "\(Int(value.rounded())) km/h"
        case .cadence: return "\(Int(value.rounded())) /min"
        case .strokeRate: return "\(Int(value.rounded())) Züge/min"
        case .perceivedEffort: return "Anstrengung \(Int(value.rounded())) von 10"
        }
    }

    /// Detailzeile eines Schritts: Ziel und Pause, soweit vorhanden.
    public static func stepDetails(_ step: PlanStep) -> String {
        var parts: [String] = []
        if let target = target(step) {
            parts.append(target)
        }
        if step.restSeconds > 0 {
            parts.append("\(PlanFormatting.rest(step.restSeconds)) Pause")
        }
        return parts.joined(separator: " · ")
    }

    /// Ein Leistungswert in der Einheit aus dem Vertrag: "1:45 /100 m", "4:50 /km", "165 bpm", "250 W", "7:05 min".
    public static func performanceValue(_ value: Double, unit: String) -> String {
        switch unit {
        case "s/100m": return "\(PlanFormatting.pace(value)) /100 m"
        case "s/km": return "\(PlanFormatting.pace(value)) /km"
        case "s": return "\(PlanFormatting.pace(value)) min"
        default: return "\(Int(value.rounded())) \(unit)"
        }
    }

    /// Ob ein Leistungswert als Zeit (Minuten:Sekunden) eingegeben wird.
    public static func isTimeUnit(_ unit: String) -> Bool {
        unit == "s/100m" || unit == "s/km" || unit == "s"
    }

    /// Liest "1:45" oder "105" als Sekunden; `nil` bei allem anderen.
    public static func parseTime(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            // Nur endliche Zahlen ab 0: "-5", "nan" oder "inf" sind keine Zeit.
            guard let seconds = Double(parts[0]), seconds.isFinite, seconds >= 0 else { return nil }
            return seconds
        case 2:
            guard let minutes = Int(parts[0]), let seconds = Int(parts[1]), minutes >= 0, (0..<60).contains(seconds), parts[1].count == 2 else { return nil }
            return Double(minutes * 60 + seconds)
        default:
            return nil
        }
    }

    /// Woher ein Leistungswert stammt, für die Profil-Ansicht.
    public static func origin(_ origin: PerformanceOrigin) -> String {
        switch origin {
        case .tested: return "Test"
        case .manual: return "von dir eingetragen"
        case .estimated: return "geschätzt"
        case .formula: return "Faustformel"
        }
    }

    /// Wie ein Tag der Woche im Vergleich zum Plan steht, ohne Sportart im Text ("nicht trainiert").
    public static func stateText(_ state: WeekDayState) -> String {
        switch state {
        case .missed: return "nicht trainiert"
        case .restBroken: return "trotz Ruhetag trainiert"
        default: return PlanFormatting.stateText(state)
        }
    }

    /// Wie ein Tag im Verlauf ausging, ohne Sportart im Text.
    public static func outcomeText(_ outcome: AdherenceOutcome) -> String {
        switch outcome {
        case .followed: return "umgesetzt"
        case .shorter: return "kürzer"
        case .longer: return "länger"
        case .missed: return "nicht trainiert"
        case .restKept: return "Ruhetag eingehalten"
        case .restBroken: return "trotz Ruhetag trainiert"
        case .pending: return "offen"
        }
    }

    /// Gemacht gegen geplant in der Einheit der Sportart: "1.200 m von 1.500 m"; ohne Plan nur das Gemachte.
    public static func comparison(planned: Double, actual: Double, unit: PlanUnit) -> String {
        guard planned > 0 else { return amount(actual, unit: unit) }
        return "\(amount(actual, unit: unit)) von \(amount(planned, unit: unit))"
    }

    /// Kurzfassung eines geplanten Tages: "Schwimmen · 2.000 m, Laufen · 40 min", "Ruhetag", "keine Zeit".
    public static func daySummary(_ day: PlannedDay?, registry: SportRegistry = .standard) -> String {
        guard let day else { return "nicht geplant" }
        if day.isUnavailable { return "keine Zeit" }
        if day.isRestDay { return "Ruhetag" }
        return day.sessions.map { sessionTitle(sport: $0.sport, amount: $0.amount, unit: $0.unit, registry: registry) }.joined(separator: ", ")
    }

    /// Ein Wochenumfang des Gesamtplans: "Schwimmen 6.000 m in 3 Einheiten".
    public static func macroVolume(_ volume: MacroSportVolume, registry: SportRegistry = .standard) -> String {
        let sessions = volume.sessions == 1 ? "1 Einheit" : "\(volume.sessions) Einheiten"
        return "\(registry.displayName(for: volume.sport)) \(amount(volume.amount, unit: volume.unit)) in \(sessions)"
    }

    /// Änderung in Prozent mit Vorzeichen: "+4 %", "−12 %", "±0 %".
    public static func changePercent(_ percent: Double) -> String {
        let rounded = Int(percent.rounded())
        if rounded > 0 { return "+\(rounded) %" }
        if rounded < 0 { return "−\(-rounded) %" }
        return "±0 %"
    }

    /// Hinweis auf der Watch, wenn der gezeigte Plan nicht von heute ist, sonst `nil`.
    public static func dayNotice(_ response: DayPlanV2Response, now: Date, calendar: Calendar = .current) -> String? {
        guard response.date != PlanFormatting.isoDay(now, calendar: calendar) else { return nil }
        return "Plan vom \(PlanFormatting.germanDate(response.date)). Öffne die iPhone-App für den Plan von heute."
    }

    /// Hinweis, wenn der Tagesplan nicht frisch von Claude kommt, sonst `nil`.
    public static func sourceNotice(_ response: DayPlanV2Response) -> String? {
        guard response.source == .fallback else { return nil }
        let reason = PlanFormatting.fallbackReason(response.fallbackReason)
        if response.stale {
            return "Letzter gültiger Plan vom \(PlanFormatting.germanDate(response.date)). \(reason)"
        }
        return "Früherer Plan von heute. \(reason)"
    }
}
