import Foundation

/// Woher ein Leistungswert stammt. Die Raw-Werte sind Teil des Vertrags mit dem Server.
public enum PerformanceOrigin: String, Codable, Sendable, CaseIterable {
    /// Aus einem Leistungstest, vom Athleten bestätigt.
    case tested
    /// Vom Athleten selbst eingetragen.
    case manual
    /// Aus Health geschätzt (z. B. höchster gemessener Puls).
    case estimated
    /// Aus einer Faustformel (z. B. 208 − 0,7 × Alter).
    case formula

    /// Höher gewinnt: Bestätigtes vor Geschätztem vor Faustformel.
    var rank: Int {
        switch self {
        case .tested, .manual: return 2
        case .estimated: return 1
        case .formula: return 0
        }
    }

    /// Vom Athleten bestätigt; nur solche Werte speichert das Profil.
    public var isConfirmed: Bool { rank == 2 }
}

/// Ein Leistungswert mit Herkunft und Datum. `sport == nil`: gilt für alle Sportarten (Maximal- und Ruhepuls).
public struct PerformanceValue: Codable, Equatable, Sendable {
    public let sport: SportID?
    public let metric: PerformanceMetric
    public let value: Double
    public let source: PerformanceOrigin
    /// Wann der Wert ermittelt wurde (Testtag, Eingabe oder Zeitpunkt der Schätzung).
    public let measuredAt: Date

    public init(sport: SportID? = nil, metric: PerformanceMetric, value: Double, source: PerformanceOrigin, measuredAt: Date) {
        self.sport = sport
        self.metric = metric
        self.value = value
        self.source = source
        self.measuredAt = measuredAt
    }

    func hasKey(metric: PerformanceMetric, sport: SportID?) -> Bool {
        self.metric == metric && self.sport == sport
    }
}

/// Die bestätigten Leistungswerte des Athleten (aus Tests und eigenen Eingaben), mit Verlauf.
///
/// Schätzungen aus Health speichert das Profil nicht: Sie entstehen bei jedem Snapshot neu (`PerformanceEstimator`)
/// und kommen erst beim Auflösen (`ResolvedPerformance`) dazu. So veraltet keine Schätzung im Speicher.
public struct PerformanceProfile: Codable, Equatable, Sendable {
    /// Wie viele Werte der Verlauf je Sportart und Leistungswert behält.
    public static let historyLimit = 12

    public let values: [PerformanceValue]

    public init(values: [PerformanceValue] = []) {
        self.values = values
    }

    public static let empty = PerformanceProfile()

    /// Verlauf eines Werts, ältester zuerst.
    public func history(of metric: PerformanceMetric, sport: SportID? = nil) -> [PerformanceValue] {
        values.filter { $0.hasKey(metric: metric, sport: sport) }.sorted { $0.measuredAt < $1.measuredAt }
    }

    /// Das Profil mit einem weiteren Wert; der Verlauf behält je Wert die neuesten `historyLimit`.
    public func recording(_ value: PerformanceValue) -> PerformanceProfile {
        let history = (self.history(of: value.metric, sport: value.sport) + [value]).sorted { $0.measuredAt < $1.measuredAt }
        let others = values.filter { !$0.hasKey(metric: value.metric, sport: value.sport) }
        return PerformanceProfile(values: others + history.suffix(Self.historyLimit))
    }
}

/// Ein bestätigter Leistungswert, der seit einem Zeitpunkt neu ist (Test oder Eingabe), mit dem Wert, der davor galt.
/// Geht an die Fortschreibung des Gesamtplans, damit Claude sieht, was sich seit dem letzten Stand getan hat.
public struct PerformanceChange: Equatable, Sendable {
    public let sport: SportID?
    public let metric: PerformanceMetric
    /// Der bestätigte Wert zum Zeitpunkt; `nil`, wenn es keinen gab.
    public let previous: Double?
    public let value: Double
    public let source: PerformanceOrigin
    public let measuredAt: Date

    public init(sport: SportID?, metric: PerformanceMetric, previous: Double?, value: Double, source: PerformanceOrigin, measuredAt: Date) {
        self.sport = sport
        self.metric = metric
        self.previous = previous
        self.value = value
        self.source = source
        self.measuredAt = measuredAt
    }
}

public extension PerformanceProfile {
    /// Je Sportart und Leistungswert der neueste bestätigte Wert nach `date`, mit dem Wert, der an `date` galt. Hat sich
    /// der Wert nicht geändert, fehlt er.
    func changes(since date: Date) -> [PerformanceChange] {
        var seen = Set<String>()
        let keys = values.filter { seen.insert("\($0.sport?.rawValue ?? "")|\($0.metric.rawValue)").inserted }
        return keys.compactMap { key -> PerformanceChange? in
            let history = self.history(of: key.metric, sport: key.sport).filter(\.source.isConfirmed)
            guard let latest = history.last, latest.measuredAt > date else { return nil }
            let previous = history.last { $0.measuredAt <= date }?.value
            guard previous != latest.value else { return nil }
            return PerformanceChange(
                sport: latest.sport, metric: latest.metric, previous: previous, value: latest.value, source: latest.source, measuredAt: latest.measuredAt
            )
        }
    }
}

/// Der gültige Wert je Sportart und Leistungswert, aus bestätigten Werten und Schätzungen.
///
/// Regeln: Bestätigtes (Test, Eingabe) geht vor Geschätztem, Geschätztes vor Faustformel; bei gleicher Herkunft
/// gilt der neuere Wert. Ausnahme `observedHigherWins` (Maximalpuls): Eine höhere Schätzung aus Messwerten löst
/// jeden anderen Wert ab. Werte außerhalb des plausiblen Bereichs und Werte, die keine Sportart kennt, fallen weg.
public struct ResolvedPerformance: Equatable, Sendable {
    /// Ein Wert je Sportart und Leistungswert: zuerst die für alle Sportarten, dann je Sportart in der Reihenfolge
    /// der Registry und der Werte des Moduls.
    public let values: [PerformanceValue]

    public init(profile: PerformanceProfile, estimates: [PerformanceValue], registry: SportRegistry = .standard) {
        let candidates = profile.values + estimates
        var keys: [(SportID?, PerformanceMetricDefinition)] = []
        for definition in PerformanceMetricDefinition.athlete {
            keys.append((nil, definition))
        }
        for module in registry.modules {
            for definition in module.performanceMetrics {
                keys.append((module.id, definition))
            }
        }
        var resolved: [PerformanceValue] = []
        for (sport, definition) in keys {
            let matching = candidates.filter { $0.hasKey(metric: definition.metric, sport: sport) }
            if let best = Self.best(of: matching, definition: definition) {
                resolved.append(best)
            }
        }
        values = resolved
    }

    static func best(of candidates: [PerformanceValue], definition: PerformanceMetricDefinition) -> PerformanceValue? {
        let plausible = candidates.filter { definition.plausibleRange.contains($0.value) }
        let ordered = plausible.sorted { first, second in
            first.source.rank != second.source.rank
                ? first.source.rank > second.source.rank
                : first.measuredAt > second.measuredAt
        }
        guard let preferred = ordered.first else { return nil }
        if definition.observedHigherWins,
           let observed = plausible.filter({ $0.source == .estimated }).max(by: { $0.value < $1.value }),
           observed.value > preferred.value {
            return observed
        }
        return preferred
    }

    /// Der Wert einer Sportart (`sport == nil`: für alle Sportarten).
    public func value(_ metric: PerformanceMetric, sport: SportID? = nil) -> PerformanceValue? {
        values.first { $0.hasKey(metric: metric, sport: sport) }
    }

    /// Der Wert der Sportart, sonst der für alle Sportarten (Grundlage einer Zone).
    public func basis(_ metric: PerformanceMetric, sport: SportID) -> PerformanceValue? {
        value(metric, sport: sport) ?? value(metric, sport: nil)
    }

    /// Die Zonen einer Sportart, soweit ihre Grundwerte bekannt sind.
    public func zones(for module: any SportModule) -> [TrainingZones] {
        module.zoneSchemes.compactMap { scheme in
            basis(scheme.basis, sport: module.id).map { scheme.zones(basisValue: $0.value) }
        }
    }

    /// Die Form für den Snapshot: Werte für alle Sportarten und je Sportart Werte und Zonen. Sportarten ohne
    /// einen Wert fehlen.
    public func summary(sports: [SportID], registry: SportRegistry = .standard) -> AthleteStateSnapshot.PerformanceSummary {
        let athlete = values.filter { $0.sport == nil }.map { AthleteStateSnapshot.PerformanceSummary.Value($0) }
        let perSport = sports.compactMap { sport -> AthleteStateSnapshot.PerformanceSummary.Sport? in
            guard let module = registry.module(for: sport) else { return nil }
            let own = values.filter { $0.sport == sport }.map { AthleteStateSnapshot.PerformanceSummary.Value($0) }
            let sportZones = self.zones(for: module)
            guard !own.isEmpty || !sportZones.isEmpty else { return nil }
            return AthleteStateSnapshot.PerformanceSummary.Sport(sport: sport, values: own, zones: sportZones)
        }
        return AthleteStateSnapshot.PerformanceSummary(athlete: athlete, sports: perSport)
    }
}
