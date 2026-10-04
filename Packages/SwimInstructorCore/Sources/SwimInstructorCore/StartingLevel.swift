import Foundation

/// Der Trainingsstand, den der Athlet zu seinem Startniveau angibt. Die Raw-Werte sind Teil des Snapshots
/// (`starting_levels[].status`) und dürfen nicht umbenannt werden.
public enum TrainingStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case regular
    case shortBreak = "short_break"
    case longBreak = "long_break"
    case beginner

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .regular: return "Trainiere regelmäßig"
        case .shortBreak: return "Pause von 2 bis 8 Wochen"
        case .longBreak: return "Pause über 8 Wochen"
        case .beginner: return "Einsteiger"
        }
    }
}

/// Was der Athlet in einer Sportart zurzeit schafft (oder vor einer Pause geschafft hat), weil Health oft weniger zeigt:
/// Training ohne Uhr, eine Pause, ein neues Gerät. Umfänge in der Einheit der Sportart (`SportModule.planUnit`: Meter
/// oder Minuten).
///
/// Geht als `starting_levels` im Snapshot v2 zum Server. Wie viel davon zählt, entscheidet der Server je Sportart und
/// Trainingsstand (docs/multisport-planning.md, "Selbst angegebenes Startniveau").
public struct StartingLevel: Codable, Equatable, Sendable, Identifiable {
    public var sport: SportID
    /// Wochenumfang.
    public var weeklyAmount: Double
    /// Längste Einheit, die ohne Probleme geht.
    public var longestSession: Double
    public var status: TrainingStatus
    public var reportedAt: Date

    public var id: SportID { sport }

    /// So lange gilt eine Angabe, danach zählt nur noch Health. Gegenstück: `MULTI_RULES.startingLevelValidDays`.
    public static let validDays = 28

    public init(sport: SportID, weeklyAmount: Double, longestSession: Double, status: TrainingStatus, reportedAt: Date) {
        self.sport = sport
        self.weeklyAmount = weeklyAmount
        self.longestSession = longestSession
        self.status = status
        self.reportedAt = reportedAt
    }

    /// Bis wann die Angabe gilt.
    public var validUntil: Date {
        reportedAt.addingTimeInterval(TimeInterval(Self.validDays * 86_400))
    }

    /// Gilt die Angabe noch (nicht älter als `validDays`)?
    public func isValid(now: Date) -> Bool {
        reportedAt <= now.addingTimeInterval(86_400) && now <= validUntil
    }

    /// Bereich, den die Eingabe zulässt: Wochenumfang bzw. längste Einheit in der Einheit der Sportart.
    public static func weeklyRange(for unit: PlanUnit) -> ClosedRange<Double> {
        switch unit {
        case .meters: return 0...50_000
        case .minutes: return 0...2_400
        }
    }

    public static func longestRange(for unit: PlanUnit) -> ClosedRange<Double> {
        switch unit {
        case .meters: return 0...10_000
        case .minutes: return 0...600
        }
    }

    /// Schrittweite der Eingabe.
    public static func step(for unit: PlanUnit) -> Double {
        switch unit {
        case .meters: return 100
        case .minutes: return 5
        }
    }
}

/// Speichert die selbst angegebenen Startniveaus auf dem Gerät, je Sportart höchstens eins.
public protocol StartingLevelStoring {
    /// Alle Angaben in der Reihenfolge der Registry, auch abgelaufene (die App zeigt sie zum Erneuern).
    func levels() -> [StartingLevel]
    /// Speichert eine Angabe für eine bekannte Sportart mit Umfängen im erlaubten Bereich; sonst bleibt alles und es
    /// kommt `false`.
    @discardableResult func setLevel(_ level: StartingLevel) -> Bool
    func removeLevel(for sport: SportID)
}

public struct UserDefaultsStartingLevelStore: StartingLevelStoring {
    static let storageKey = "settings.startingLevels"

    private let defaults: UserDefaults
    private let registry: SportRegistry

    public init(defaults: UserDefaults = .standard, registry: SportRegistry = .standard) {
        self.defaults = defaults
        self.registry = registry
    }

    public func levels() -> [StartingLevel] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode([StartingLevel].self, from: data) else { return [] }
        return sorted(stored.filter { registry.module(for: $0.sport) != nil })
    }

    @discardableResult
    public func setLevel(_ level: StartingLevel) -> Bool {
        guard let module = registry.module(for: level.sport),
              StartingLevel.weeklyRange(for: module.planUnit).contains(level.weeklyAmount),
              StartingLevel.longestRange(for: module.planUnit).contains(level.longestSession) else { return false }
        let others = levels().filter { $0.sport != level.sport }
        return save(others + [level])
    }

    public func removeLevel(for sport: SportID) {
        _ = save(levels().filter { $0.sport != sport })
    }

    private func save(_ levels: [StartingLevel]) -> Bool {
        guard let data = try? JSONEncoder().encode(sorted(levels)) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    private func sorted(_ levels: [StartingLevel]) -> [StartingLevel] {
        levels.sorted { (registry.ids.firstIndex(of: $0.sport) ?? .max) < (registry.ids.firstIndex(of: $1.sport) ?? .max) }
    }
}

/// Texte und Vorschläge für die Eingabe des Startniveaus. Im Package, damit sie per Unit-Test prüfbar sind.
public enum StartingLevelFormatting {
    /// Was Health in den letzten 4 Wochen gezeigt hat, in der Einheit der Sportart.
    public static func healthSummary(_ state: AthleteStateSnapshot.SportStateSummary?, unit: PlanUnit) -> String {
        guard let state, state.sessionsLastFourWeeks > 0 else { return "Health: keine Einheiten in den letzten 4 Wochen." }
        let (average, longest) = amounts(state, unit: unit)
        return "Health (letzte 4 Wochen): im Schnitt \(PlanV2Formatting.amount(average, unit: unit)) pro Woche, " +
            "längste Einheit \(PlanV2Formatting.amount(longest, unit: unit))."
    }

    /// Bis wann die Angabe gilt, oder dass sie abgelaufen ist.
    public static func validity(_ level: StartingLevel, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.timeZone = calendar.timeZone
        let day = formatter.string(from: level.validUntil)
        return level.isValid(now: now)
            ? "Gilt bis \(day). Danach zählt nur noch, was Health aufzeichnet; eine Änderung verlängert sie."
            : "Abgelaufen am \(day), der Plan rechnet wieder nur mit Health. Eine Änderung erneuert sie."
    }

    /// Kurzfassung für die Einstellungen: wie viele Sportarten eine gültige Angabe haben.
    public static func summary(_ levels: [StartingLevel], now: Date) -> String {
        let valid = levels.filter { $0.isValid(now: now) }.count
        switch valid {
        case 0: return levels.isEmpty ? "Nicht angegeben" : "Abgelaufen"
        case 1: return "1 Sportart"
        default: return "\(valid) Sportarten"
        }
    }

    /// Vorschlag für eine neue Angabe: die Werte aus Health, auf die Schrittweite gerundet, Trainingsstand regelmäßig.
    public static func suggestion(
        sport: SportID, state: AthleteStateSnapshot.SportStateSummary?, unit: PlanUnit, now: Date
    ) -> StartingLevel {
        let step = StartingLevel.step(for: unit)
        let (average, longest) = state.map { amounts($0, unit: unit) } ?? (0, 0)
        let round = { (value: Double) in (value / step).rounded() * step }
        return StartingLevel(
            sport: sport,
            weeklyAmount: min(round(average), StartingLevel.weeklyRange(for: unit).upperBound),
            longestSession: min(round(longest), StartingLevel.longestRange(for: unit).upperBound),
            status: .regular,
            reportedAt: now
        )
    }

    private static func amounts(_ state: AthleteStateSnapshot.SportStateSummary, unit: PlanUnit) -> (Double, Double) {
        switch unit {
        case .meters: return (state.averageWeeklyMeters, state.longestSessionMeters)
        case .minutes: return (state.averageWeeklyMinutes, state.longestSessionMinutes)
        }
    }
}
