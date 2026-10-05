import Foundation

/// Texte für die Plan-Anzeige. Liegt im Package, damit iPhone und Watch dieselben Formulierungen
/// nutzen und sie per Unit-Test prüfbar sind.
public enum PlanFormatting {
    /// 140 → "2:20" (Minuten:Sekunden pro 100 m).
    public static func pace(_ secondsPerHundredMeters: Double) -> String {
        let total = Int(secondsPerHundredMeters.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 1600 → "1.600 m" (deutsche Tausenderpunkte, unabhängig von der Gerätesprache).
    public static func meters(_ meters: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return "\(formatter.string(from: NSNumber(value: meters)) ?? String(meters)) m"
    }

    /// Strecke einer Einheit beliebiger Sportart: bis 5 km in Metern ("1.600 m"), darüber in Kilometern mit einer
    /// Nachkommastelle ("42,2 km").
    public static func distance(_ meters: Double) -> String {
        guard meters >= 5000 else { return Self.meters(Int(meters.rounded())) }
        return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
    }

    /// 30 → "30 s", 90 → "1:30 min".
    public static func rest(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) s" }
        return String(format: "%d:%02d min", seconds / 60, seconds % 60)
    }

    /// Deutscher Name eines Hilfsmittels; Unbekanntes bleibt lesbar (aus `snake_case` wird "Snake Case").
    public static func equipmentName(_ raw: String) -> String {
        switch raw {
        case "pull_buoy": return "Pull Buoy"
        case "paddles": return "Paddles"
        case "fins": return "Flossen"
        case "snorkel": return "Schnorchel"
        case "kickboard": return "Kickboard"
        case "ankle_band": return "Beinband"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// "Pull Buoy, Paddles"; leer ohne Hilfsmittel.
    public static func equipment(_ items: [String]) -> String {
        items.map(equipmentName).joined(separator: ", ")
    }

    public static func sessionType(_ type: SessionType) -> String {
        switch type {
        case .rest: return "Ruhetag"
        case .recovery: return "Regeneration"
        case .technique: return "Technik"
        case .endurance: return "Ausdauer"
        case .threshold: return "Schwelle"
        case .intervals: return "Intervalle"
        case .test: return "Test"
        case .unknown: return "Training"
        }
    }

    public static func intensity(_ intensity: PlanIntensity) -> String {
        switch intensity {
        case .rest: return "Ruhe"
        case .easy: return "locker"
        case .moderate: return "mittel"
        case .hard: return "hart"
        case .unknown: return "unbekannt"
        }
    }

    /// Satz zum Ausfallgrund des Servers (`fallback_reason`), für Fehlermeldungen und Hinweise zum Plan.
    static func fallbackReason(_ reason: String?) -> String {
        switch reason {
        case "budget_exceeded": return "Das Tageslimit für neue Pläne ist erreicht."
        case "not_configured": return "Auf dem Server ist der Coach nicht eingerichtet."
        case "unreachable", "timeout", "rate_limited", "upstream_error":
            return "Dein Coach war gerade nicht erreichbar."
        case "sanity_blocked": return "Der neue Plan hat die Sicherheitsprüfung nicht bestanden."
        default: return "Dein Coach hat keinen neuen Plan geliefert."
        }
    }

    /// 754 → "12:34", 3723 → "1:02:03".
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Wie ein Tag der Woche im Vergleich zum Plan steht, als kurzer Text.
    public static func stateText(_ state: WeekDayState) -> String {
        switch state {
        case .unplanned: return "nicht geplant"
        case .upcoming: return "geplant"
        case .today: return "heute"
        case .followed: return "umgesetzt"
        case .shorter: return "kürzer"
        case .longer: return "länger"
        case .missed: return "nicht geschwommen"
        case .restKept: return "Ruhetag eingehalten"
        case .restBroken: return "trotz Ruhetag geschwommen"
        case .skipped: return "keine Zeit"
        }
    }

    /// Deutscher Name einer Phase des Gesamtplans.
    public static func macroPhase(_ phase: MacroPhase) -> String {
        switch phase {
        case .base: return "Aufbau"
        case .specific: return "Zielspezifisch"
        case .taper: return "Zuspitzen"
        case .goalWeek: return "Zielwoche"
        case .maintain: return "Erhalten"
        }
    }

    /// "30.09." für `2026-09-30`.
    public static func shortGermanDate(_ isoDay: String) -> String {
        let parts = isoDay.split(separator: "-")
        guard parts.count == 3 else { return isoDay }
        return "\(parts[2]).\(parts[1])."
    }

    /// "2026-09-29" → "29.09.2026"; unbekannte Formate bleiben unverändert.
    public static func germanDate(_ isoDay: String) -> String {
        let parts = isoDay.split(separator: "-")
        guard parts.count == 3 else { return isoDay }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    /// Kurzform des Gesamtziels für die Einstellungen: "Triathlon Olympisch, 04.07.2027" oder bei einem eigenen
    /// Ziel die Disziplinen ("Laufen 10,0 km, 04.07.2027"). Ein Fitnessziel nennt die Sportarten und das Ende des
    /// Planungszeitraums ("Fitness: Radfahren, Laufen, bis 04.07.2027").
    public static func goalSummary(_ goal: TrainingGoal, registry: SportRegistry = .standard, calendar: Calendar = .current) -> String {
        if goal.kind == .fitness {
            let sports = goal.sports.map { registry.displayName(for: $0) }.joined(separator: ", ")
            return "Fitness: \(sports), bis \(germanDate(isoDay(goal.targetDate, calendar: calendar)))"
        }
        let what = GoalTemplate.template(id: goal.template)?.displayName
            ?? goal.disciplines.map { "\(registry.displayName(for: $0.sport)) \(distance($0.distanceMeters))" }.joined(separator: ", ")
        return "\(what), \(germanDate(isoDay(goal.targetDate, calendar: calendar)))"
    }

    /// Kalendertag im Format des Servers (`YYYY-MM-DD`).
    public static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
