import Foundation

/// Texte zum Stand in der Einheit für die Watch: Anzeige und Ansagen. Im Package, damit sie per Unit-Test prüfbar sind.
public enum ProgressFormatting {
    /// "2/5 Intervalle": Nummer des Schritts, Anzahl der Schritte und Name.
    public static func stepTitle(_ unit: ProgressUnit, stepCount: Int) -> String {
        "\(unit.stepIndex + 1)/\(max(stepCount, unit.stepIndex + 1)) \(unit.step.name)"
    }

    /// "3 von 6"; `nil` bei einem Schritt mit einer Wiederholung.
    public static func repetition(_ unit: ProgressUnit) -> String? {
        unit.step.repetitions > 1 ? String(localized: "\(unit.repetition) von \(unit.step.repetitions)") : nil
    }

    /// Umfang einer Wiederholung: "200 m", "3:00 min" bzw. "von Hand" ohne Strecke und Zeit.
    public static func target(_ unit: ProgressUnit) -> String {
        switch unit.target {
        case let .meters(meters)?: return PlanFormatting.meters(Int(meters.rounded()))
        case let .seconds(seconds)?: return "\(PlanFormatting.elapsed(seconds)) min"
        case nil: return String(localized: "von Hand")
        }
    }

    /// Was bis zum Ende fehlt: "noch 150 m", "noch 1:23", in der Pause "Pause 0:25". Ohne Ziel die Zeit seit Beginn.
    public static func remaining(_ status: ProgressStatus) -> String {
        switch status {
        case .noUnits:
            return String(localized: "Freies Training")
        case .completed:
            return String(localized: "Plan geschafft")
        case let .rest(_, _, seconds):
            let time = PlanFormatting.elapsed(TimeInterval(seconds))
            return String(localized: "Pause \(time)")
        case let .work(unit, done, remaining):
            switch (unit.target, remaining) {
            case (.meters?, let remaining?):
                let meters = PlanFormatting.meters(Int(remaining.rounded(.up)))
                return String(localized: "noch \(meters)")
            case (.seconds?, let remaining?):
                let time = PlanFormatting.elapsed(remaining.rounded(.up))
                return String(localized: "noch \(time)")
            default:
                return PlanFormatting.elapsed(done)
            }
        }
    }

    /// Kurzzeile unter dem Namen: "3 von 6 · noch 150 m".
    public static func line(_ status: ProgressStatus) -> String {
        switch status {
        case let .work(unit, _, _):
            return [repetition(unit), remaining(status)].compactMap { $0 }.joined(separator: " · ")
        default:
            return remaining(status)
        }
    }

    /// Kurztext für die Uhr: der Hinweis des Plans, sonst Umfang und Ziel.
    public static func cue(_ unit: ProgressUnit) -> String {
        if !unit.step.cue.isEmpty { return unit.step.cue }
        return [target(unit), PlanV2Formatting.target(unit.step)].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Ansagen

    /// Was die Watch beim Ereignis sagt; `nil`, wenn sie still bleibt (Ende einer Wiederholung außerhalb eines Tests).
    public static func announcement(_ event: ProgressEvent) -> String? {
        switch event {
        case let .workStarted(unit):
            let name = repetition(unit).map { "\(unit.step.name), \($0)" } ?? unit.step.name
            return "\(name). \(cue(unit))."
        case let .restStarted(unit):
            let duration = spokenDuration(TimeInterval(unit.restSeconds))
            return String(localized: "Pause, \(duration).")
        case let .workEnded(segment):
            guard segment.unit.step.isTestEffort, segment.reachedTarget else { return nil }
            let duration = spokenDuration(segment.duration)
            return String(localized: "Geschafft. Zeit \(duration).")
        case .completed:
            return String(localized: "Plan geschafft.")
        }
    }

    /// Zum Vorlesen: "45 Sekunden", "1 Minute", "6 Minuten 12".
    public static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        guard total >= 60 else { return String(localized: "\(total) Sekunden") }
        let minutes = total / 60
        let rest = total % 60
        if minutes == 1 {
            return rest == 0 ? String(localized: "1 Minute") : String(localized: "1 Minute \(rest)")
        }
        return rest == 0 ? String(localized: "\(minutes) Minuten") : String(localized: "\(minutes) Minuten \(rest)")
    }
}
