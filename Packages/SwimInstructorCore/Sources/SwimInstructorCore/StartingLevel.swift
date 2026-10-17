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
        case .regular: return String(localized: "Trainiere regelmäßig")
        case .shortBreak: return String(localized: "Pause von 2 bis 8 Wochen")
        case .longBreak: return String(localized: "Pause über 8 Wochen")
        case .beginner: return String(localized: "Einsteiger")
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
    /// Übliches Tempo, optional, in der Einheit von `SportModule.startingPace` (s/100m, s/km oder km/h).
    public var pace: Double?
    /// Aktuelle Bestzeiten über Strecken aus `SportModule.bestTimeDistances`, je Strecke höchstens eine; `nil` ohne.
    public var bestTimes: [BestTime]?

    /// Eine Bestzeit: Strecke in Metern und Zeit in Sekunden.
    public struct BestTime: Codable, Equatable, Sendable {
        public var distanceMeters: Int
        public var seconds: Double

        public init(distanceMeters: Int, seconds: Double) {
            self.distanceMeters = distanceMeters
            self.seconds = seconds
        }
    }

    public var id: SportID { sport }

    /// So lange gilt eine Angabe, danach zählt nur noch Health. Gegenstück: `MULTI_RULES.startingLevelValidDays`.
    public static let validDays = 28

    public init(
        sport: SportID, weeklyAmount: Double, longestSession: Double, status: TrainingStatus, reportedAt: Date,
        pace: Double? = nil, bestTimes: [BestTime]? = nil
    ) {
        self.sport = sport
        self.weeklyAmount = weeklyAmount
        self.longestSession = longestSession
        self.status = status
        self.reportedAt = reportedAt
        self.pace = pace
        self.bestTimes = bestTimes
    }

    /// Passen Tempo und Bestzeiten zur Sportart? Tempo im Bereich von `startingPace`, Bestzeiten je einmal über Strecken
    /// aus `bestTimeDistances` mit plausiblem Tempo (`goalSpeedRange`). Ohne Angabe immer.
    public func hasValidPace(for module: any SportModule) -> Bool {
        if let pace, !(module.startingPace?.range.contains(pace) ?? false) { return false }
        let times = bestTimes ?? []
        guard Set(times.map(\.distanceMeters)).count == times.count else { return false }
        return times.allSatisfy { best in
            module.bestTimeDistances.contains(best.distanceMeters) && best.seconds > 0
                && module.goalSpeedRange.contains(Double(best.distanceMeters) / best.seconds)
        }
    }

    /// Die Bestzeit über eine Strecke, `nil` ohne.
    public func bestTime(over meters: Int) -> Double? {
        bestTimes?.first { $0.distanceMeters == meters }?.seconds
    }

    /// Setzt oder löscht (`nil`) die Bestzeit über eine Strecke; ohne Bestzeit bleibt `bestTimes` `nil`.
    public mutating func setBestTime(_ seconds: Double?, over meters: Int) {
        var times = (bestTimes ?? []).filter { $0.distanceMeters != meters }
        if let seconds { times.append(BestTime(distanceMeters: meters, seconds: seconds)) }
        bestTimes = times.isEmpty ? nil : times.sorted { $0.distanceMeters < $1.distanceMeters }
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
              StartingLevel.longestRange(for: module.planUnit).contains(level.longestSession),
              level.hasValidPace(for: module) else { return false }
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
        guard let state, state.sessionsLastFourWeeks > 0 else { return String(localized: "Health: keine Einheiten in den letzten 4 Wochen.") }
        let (average, longest) = amounts(state, unit: unit)
        let averageText = PlanV2Formatting.amount(average, unit: unit)
        let longestText = PlanV2Formatting.amount(longest, unit: unit)
        return String(localized: "Health (letzte 4 Wochen): im Schnitt \(averageText) pro Woche, längste Einheit \(longestText).")
    }

    /// Bis wann die Angabe gilt, oder dass sie abgelaufen ist.
    public static func validity(_ level: StartingLevel, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.setLocalizedDateFormatFromTemplate("ddMMyyyy")
        formatter.timeZone = calendar.timeZone
        let day = formatter.string(from: level.validUntil)
        return level.isValid(now: now)
            ? String(localized: "Gilt bis \(day). Danach zählt nur noch, was Health aufzeichnet; eine Änderung verlängert sie.")
            : String(localized: "Abgelaufen am \(day), der Plan rechnet wieder nur mit Health. Eine Änderung erneuert sie.")
    }

    /// Kurzfassung für die Einstellungen: wie viele Sportarten eine gültige Angabe haben.
    public static func summary(_ levels: [StartingLevel], now: Date) -> String {
        let valid = levels.filter { $0.isValid(now: now) }.count
        switch valid {
        case 0: return levels.isEmpty ? String(localized: "Nicht angegeben") : String(localized: "Abgelaufen")
        case 1: return String(localized: "1 Sportart")
        default: return String(localized: "\(valid) Sportarten")
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

    /// Das Tempo zum Anzeigen im Eingabefeld: "2:05" (Pace) oder "27,5" (km/h).
    public static func paceText(_ value: Double, pace: StartingPace) -> String {
        guard pace.target == .speed else { return PlanFormatting.pace(value) }
        return value.formatted(.number.precision(.fractionLength(0...1)).locale(AppLocale.current))
    }

    /// Liest ein Tempo: "2:05" als Sekunden (Pace) oder "27,5" als km/h. `nil` bei allem anderen.
    public static func parsePace(_ text: String, pace: StartingPace) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard pace.target == .speed else { return PlanV2Formatting.parseTime(trimmed) }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return value
    }

    /// Einheit hinter dem Tempo-Feld: "/100 m", "/km" oder "km/h".
    public static func paceUnit(_ pace: StartingPace) -> String {
        switch pace.target {
        case .pacePerHundredMeters: return "/100 m"
        case .pacePerKilometer: return "/km"
        default: return "km/h"
        }
    }

    /// Eine Bestzeit zum Anzeigen: 1500 → "25:00", 3930 → "1:05:30".
    public static func clockText(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, total % 3600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Liest "25:00" oder "1:05:30" als Sekunden; `nil` bei allem anderen.
    public static func parseClock(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return parts.count == 2 ? PlanV2Formatting.parseTime(text) : nil }
        guard let hours = Int(parts[0]), hours >= 0, parts[1].count == 2, parts[2].count == 2,
              let minutes = Int(parts[1]), let seconds = Int(parts[2]), (0..<60).contains(minutes), (0..<60).contains(seconds)
        else { return nil }
        return Double(hours * 3600 + minutes * 60 + seconds)
    }

    /// "5 km", "10 km" oder "800 m".
    public static func distanceText(_ meters: Int) -> String {
        meters % 1000 == 0 ? "\(meters / 1000) km" : "\(meters) m"
    }

    private static func amounts(_ state: AthleteStateSnapshot.SportStateSummary, unit: PlanUnit) -> (Double, Double) {
        switch unit {
        case .meters: return (state.averageWeeklyMeters, state.longestSessionMeters)
        case .minutes: return (state.averageWeeklyMinutes, state.longestSessionMinutes)
        }
    }
}
