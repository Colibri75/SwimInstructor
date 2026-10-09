import Foundation

/// Texte für die Plan-Anzeige. Liegt im Package, damit iPhone und Watch dieselben Formulierungen
/// nutzen und sie per Unit-Test prüfbar sind.
public enum PlanFormatting {
    /// 140 → "2:20" (Minuten:Sekunden pro 100 m).
    public static func pace(_ secondsPerHundredMeters: Double) -> String {
        let total = Int(secondsPerHundredMeters.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 1600 → "1.600 m" (Tausendertrennzeichen in der Sprache der App).
    public static func meters(_ meters: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocale.current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return "\(formatter.string(from: NSNumber(value: meters)) ?? String(meters)) m"
    }

    /// Strecke einer Einheit beliebiger Sportart: bis 5 km in Metern ("1.600 m"), darüber in Kilometern mit einer
    /// Nachkommastelle ("42,2 km").
    public static func distance(_ meters: Double) -> String {
        guard meters >= 5000 else { return Self.meters(Int(meters.rounded())) }
        return String(format: "%.1f km", locale: AppLocale.current, meters / 1000)
    }

    /// 30 → "30 s", 90 → "1:30 min".
    public static func rest(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) s" }
        return String(format: "%d:%02d min", seconds / 60, seconds % 60)
    }

    /// Deutscher Name eines Hilfsmittels; Unbekanntes bleibt lesbar (aus `snake_case` wird "Snake Case").
    public static func equipmentName(_ raw: String) -> String {
        switch raw {
        case "pull_buoy": return String(localized: "Pull Buoy")
        case "paddles": return String(localized: "Paddles")
        case "fins": return String(localized: "Flossen")
        case "snorkel": return String(localized: "Schnorchel")
        case "kickboard": return String(localized: "Kickboard")
        case "ankle_band": return String(localized: "Beinband")
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// "Pull Buoy, Paddles"; leer ohne Hilfsmittel.
    public static func equipment(_ items: [String]) -> String {
        items.map(equipmentName).joined(separator: ", ")
    }

    public static func sessionType(_ type: SessionType) -> String {
        switch type {
        case .rest: return String(localized: "Ruhetag")
        case .recovery: return String(localized: "Regeneration")
        case .technique: return String(localized: "Technik")
        case .endurance: return String(localized: "Ausdauer")
        case .threshold: return String(localized: "Schwelle")
        case .intervals: return String(localized: "Intervalle")
        case .test: return String(localized: "Test")
        case .unknown: return String(localized: "Training")
        }
    }

    public static func intensity(_ intensity: PlanIntensity) -> String {
        switch intensity {
        case .rest: return String(localized: "Ruhe", comment: "Intensität: Ruhetag")
        case .easy: return String(localized: "locker", comment: "Intensität")
        case .moderate: return String(localized: "mittel", comment: "Intensität")
        case .hard: return String(localized: "hart", comment: "Intensität")
        case .unknown: return String(localized: "unbekannt", comment: "Intensität")
        }
    }

    /// Satz zum Ausfallgrund des Servers (`fallback_reason`), für Fehlermeldungen und Hinweise zum Plan.
    static func fallbackReason(_ reason: String?) -> String {
        switch reason {
        case "budget_exceeded": return String(localized: "Das Stunden- oder Tageslimit für neue Pläne ist erreicht (10 pro Stunde, 20 pro Tag). Versuch es später noch einmal.")
        case "not_configured": return String(localized: "Auf dem Server ist der Coach nicht eingerichtet.")
        case "unreachable", "timeout", "rate_limited", "upstream_error":
            return String(localized: "Dein Coach war gerade nicht erreichbar.")
        case "sanity_blocked": return String(localized: "Der neue Plan hat die Sicherheitsprüfung nicht bestanden.")
        default: return String(localized: "Dein Coach hat keinen neuen Plan geliefert.")
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
        case .unplanned: return String(localized: "nicht geplant")
        case .upcoming: return String(localized: "geplant")
        case .today: return String(localized: "heute")
        case .followed: return String(localized: "umgesetzt")
        case .shorter: return String(localized: "kürzer")
        case .longer: return String(localized: "länger")
        case .missed: return String(localized: "nicht geschwommen")
        case .restKept: return String(localized: "Ruhetag eingehalten")
        case .restBroken: return String(localized: "trotz Ruhetag geschwommen")
        case .skipped: return String(localized: "keine Zeit")
        }
    }

    /// Deutscher Name einer Phase des Gesamtplans.
    public static func macroPhase(_ phase: MacroPhase) -> String {
        switch phase {
        case .base: return String(localized: "Aufbau", comment: "Phase des Gesamtplans")
        case .specific: return String(localized: "Zielspezifisch", comment: "Phase des Gesamtplans")
        case .taper: return String(localized: "Zuspitzen", comment: "Phase des Gesamtplans")
        case .goalWeek: return String(localized: "Zielwoche", comment: "Phase des Gesamtplans")
        case .maintain: return String(localized: "Erhalten", comment: "Phase des Gesamtplans")
        }
    }

    /// "30.09." für `2026-09-30` (Format der Sprache der App).
    public static func shortGermanDate(_ isoDay: String) -> String {
        formattedDay(isoDay, template: "ddMM") ?? isoDay
    }

    /// "2026-09-29" → "29.09.2026" (Format der Sprache der App); unbekannte Formate bleiben unverändert.
    public static func germanDate(_ isoDay: String) -> String {
        formattedDay(isoDay, template: "ddMMyyyy") ?? isoDay
    }

    /// Ein Kalendertag `yyyy-MM-dd` im Datumsformat der App-Sprache; `nil` bei einem ungültigen Tag.
    private static func formattedDay(_ isoDay: String, template: String) -> String? {
        let parts = isoDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = AppLocale.current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// Kurzform des Gesamtziels für die Einstellungen: "Triathlon Olympisch, 04.07.2027" oder bei einem eigenen
    /// Ziel die Disziplinen ("Laufen 10,0 km, 04.07.2027"). Ein Fitnessziel nennt die Sportarten und das Ende des
    /// Planungszeitraums ("Fitness: Radfahren, Laufen, bis 04.07.2027").
    public static func goalSummary(_ goal: TrainingGoal, registry: SportRegistry = .standard, calendar: Calendar = .current) -> String {
        if goal.kind == .fitness {
            let sports = goal.sports.map { registry.displayName(for: $0) }.joined(separator: ", ")
            let day = germanDate(isoDay(goal.targetDate, calendar: calendar))
            return String(localized: "Fitness: \(sports), bis \(day)")
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
