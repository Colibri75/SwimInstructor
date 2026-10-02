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

    /// 30 → "30 s", 90 → "1:30 min".
    public static func rest(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds) s" }
        return String(format: "%d:%02d min", seconds / 60, seconds % 60)
    }

    /// "6 × 200 m" bzw. "400 m" bei einer Wiederholung.
    public static func setVolume(_ set: PlanSet) -> String {
        set.repetitions > 1
            ? "\(set.repetitions) × \(meters(set.distanceMeters))"
            : meters(set.distanceMeters)
    }

    /// Kurze Detailzeile: Zielpace und Pause, soweit vorhanden.
    public static func setDetails(_ set: PlanSet) -> String {
        var parts: [String] = []
        if let pace = set.targetPaceSecondsPerHundredMeters {
            parts.append("\(self.pace(pace)) /100 m")
        }
        if set.restSeconds > 0 {
            parts.append("\(rest(set.restSeconds)) Pause")
        }
        return parts.joined(separator: " · ")
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

    /// Die Kurzbeschreibung eines Abschnitts für die Uhr: das Feld `cue` des Plans, bei älteren Plänen die
    /// ersten Wörter der Anweisung (höchstens vier, ohne Satzzeichen am Ende), sonst leer.
    public static func shortCue(_ set: PlanSet, maxWords: Int = 4) -> String {
        let cue = set.cue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cue.isEmpty { return cue }
        let words = set.instructions
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(maxWords)
            .joined(separator: " ")
        return words.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?-– "))
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

    /// Hinweis, wenn der Plan nicht frisch von Claude kommt, sonst `nil`.
    public static func sourceNotice(_ response: PlanResponse) -> String? {
        guard response.source == .fallback else { return nil }
        let reason = fallbackReason(response.fallbackReason)
        if response.stale {
            return "Letzter gültiger Plan vom \(germanDate(response.date)). \(reason)"
        }
        return "Früherer Plan von heute. \(reason)"
    }

    static func fallbackReason(_ reason: String?) -> String {
        switch reason {
        case "budget_exceeded": return "Das Tageslimit für neue Pläne ist erreicht."
        case "not_configured": return "Auf dem Server ist Claude nicht eingerichtet."
        case "unreachable", "timeout", "rate_limited", "upstream_error":
            return "Claude war gerade nicht erreichbar."
        case "sanity_blocked": return "Der neue Plan hat die Sicherheitsprüfung nicht bestanden."
        default: return "Claude hat keinen neuen Plan geliefert."
        }
    }

    /// Hinweis auf der Watch, wenn der gezeigte Plan nicht von heute ist, sonst `nil`.
    public static func dayNotice(_ response: PlanResponse, now: Date, calendar: Calendar = .current) -> String? {
        guard response.date != isoDay(now, calendar: calendar) else { return nil }
        return "Plan vom \(germanDate(response.date)). Öffne die iPhone-App für den Plan von heute."
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

    /// "3 von 6 × 200 m" bzw. "400 m" bei einer Wiederholung.
    public static func repetition(_ position: PlanPosition) -> String {
        position.set.repetitions > 1
            ? "\(position.repetition) von \(position.set.repetitions) × \(meters(position.set.distanceMeters))"
            : meters(position.set.distanceMeters)
    }

    /// "noch 150 m".
    public static func remaining(_ position: PlanPosition) -> String {
        "noch \(meters(position.metersRemainingInRepetition))"
    }

    /// "2026-09-29" → "29.09.2026"; unbekannte Formate bleiben unverändert.
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

    /// Kurze Beschreibung eines Tages: "Technik, 1.000 m" oder "Ruhetag".
    public static func daySummary(_ day: WeekDayPlan?) -> String {
        guard let day else { return "nicht geplant" }
        if day.isRestDay { return day.isUnavailable ? "keine Zeit" : "Ruhetag" }
        return "\(sessionType(day.sessionType)), \(meters(day.targetDistanceMeters))"
    }

    /// "30.09." für `2026-09-30`.
    public static func shortGermanDate(_ isoDay: String) -> String {
        let parts = isoDay.split(separator: "-")
        guard parts.count == 3 else { return isoDay }
        return "\(parts[2]).\(parts[1])."
    }

    public static func germanDate(_ isoDay: String) -> String {
        let parts = isoDay.split(separator: "-")
        guard parts.count == 3 else { return isoDay }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    /// Kalendertag im Format des Servers (`YYYY-MM-DD`).
    public static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
