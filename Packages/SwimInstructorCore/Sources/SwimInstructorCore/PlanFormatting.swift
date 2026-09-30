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

    /// "2026-09-29" → "29.09.2026"; unbekannte Formate bleiben unverändert.
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
