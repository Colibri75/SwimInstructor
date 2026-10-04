import Foundation

/// Steuert die Profilansicht: Leistungswerte mit Herkunft und Verlauf anzeigen, von Hand ändern und das Ergebnis eines
/// Tests erst nach Bestätigung übernehmen. Absichtlich ohne SwiftUI, damit der Ablauf per Unit-Test prüfbar ist.
@MainActor
public final class PerformanceProfileLoader: ObservableObject {
    /// Ab dieser Änderung gegenüber dem bisherigen Wert (in Prozent) steht beim Ergebnis "bitte prüfen".
    public static let reviewThresholdPercent = 10.0

    /// Ein Leistungswert in der Ansicht.
    public struct Entry: Identifiable, Equatable {
        /// `nil`: gilt für alle Sportarten (Maximal- und Ruhepuls).
        public let sport: SportID?
        public let definition: PerformanceMetricDefinition
        /// Der gültige Wert aus Profil und Schätzungen, `nil` ohne Wert.
        public let current: PerformanceValue?
        /// Bestätigte Werte (Tests, Eingaben), ältester zuerst.
        public let history: [PerformanceValue]

        public var id: String { "\(sport?.rawValue ?? "-")|\(definition.metric.rawValue)" }
    }

    /// Ein Wert aus einem Testergebnis, noch nicht übernommen.
    public struct Proposal: Identifiable, Equatable {
        public let definition: PerformanceMetricDefinition
        public let value: Double
        /// Der bisher gültige Wert, `nil` ohne Wert.
        public let previous: PerformanceValue?

        public var id: String { definition.metric.rawValue }

        /// Änderung gegenüber dem bisherigen Wert in Prozent, `nil` ohne bisherigen Wert.
        public var changePercent: Double? {
            guard let previous, previous.value != 0 else { return nil }
            return (value - previous.value) / previous.value * 100
        }

        /// Ein Sprung über 10 %: eher ein Eingabe- oder Messfehler als ein echter Fortschritt.
        public var needsReview: Bool {
            guard let changePercent else { return false }
            return abs(changePercent) > PerformanceProfileLoader.reviewThresholdPercent
        }
    }

    /// Das Ergebnis eines Tests, das auf Bestätigung wartet.
    public struct PendingResult: Equatable {
        public let sport: SportID
        public let testID: String
        public let testName: String
        public let measuredAt: Date
        public let proposals: [Proposal]

        public var needsReview: Bool { proposals.contains(where: \.needsReview) }
    }

    @Published public private(set) var profile: PerformanceProfile
    @Published public private(set) var pending: PendingResult?
    @Published public private(set) var error: String?

    /// Die Schätzungen aus Health (aus dem letzten Snapshot); wird nach dem Anlegen gesetzt.
    public var estimatesProvider: @MainActor () -> [PerformanceValue] = { [] }

    private let store: PerformanceProfileStoring
    private let registry: SportRegistry
    private let now: () -> Date

    public init(store: PerformanceProfileStoring, registry: SportRegistry = .standard, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.registry = registry
        self.now = now
        self.profile = store.profile()
    }

    // MARK: - Lesen

    private var resolved: ResolvedPerformance {
        ResolvedPerformance(profile: profile, estimates: estimatesProvider().filter { !$0.source.isConfirmed }, registry: registry)
    }

    /// Die Werte für alle Sportarten (`sport == nil`) oder die einer Sportart, in der Reihenfolge des Moduls.
    public func entries(for sport: SportID?) -> [Entry] {
        let definitions = sport.map { registry.module(for: $0)?.performanceMetrics ?? [] } ?? PerformanceMetricDefinition.athlete
        let resolved = self.resolved
        return definitions.map { definition in
            Entry(
                sport: sport,
                definition: definition,
                current: resolved.value(definition.metric, sport: sport),
                history: profile.history(of: definition.metric, sport: sport)
            )
        }
    }

    /// Der gültige Wert, `nil` ohne Wert.
    public func current(_ metric: PerformanceMetric, sport: SportID?) -> PerformanceValue? {
        resolved.value(metric, sport: sport)
    }

    // MARK: - Ändern

    /// Trägt einen Wert von Hand ein. Er gilt sofort und steht im Verlauf. Liefert `false` bei einem Wert außerhalb des
    /// plausiblen Bereichs oder einem unbekannten Leistungswert.
    @discardableResult
    public func setManual(_ value: Double, metric: PerformanceMetric, sport: SportID?) -> Bool {
        guard let definition = registry.metricDefinition(metric, sport: sport) else {
            error = "Diesen Wert kennt die App nicht."
            return false
        }
        guard value.isFinite, definition.plausibleRange.contains(value) else {
            error = "\(definition.displayName) liegt außerhalb von \(PlanV2Formatting.performanceValue(definition.plausibleRange.lowerBound, unit: definition.unit)) bis \(PlanV2Formatting.performanceValue(definition.plausibleRange.upperBound, unit: definition.unit))."
            return false
        }
        return record([PerformanceValue(sport: sport, metric: metric, value: value, source: .manual, measuredAt: now())])
    }

    /// Wertet das Ergebnis eines Tests aus und legt es zur Bestätigung vor. Nur Tests mit Vollbelastung ändern das
    /// Profil; ein lockerer Einstiegstest liefert nur eine Schätzung, die die App selbst aus Health nimmt. Liefert
    /// `false`, wenn sich kein Wert ergibt.
    @discardableResult
    public func propose(testID: String, sport: SportID, entries: [String: Double], measuredAt: Date? = nil) -> Bool {
        guard let module = registry.module(for: sport), let test = module.performanceTests.first(where: { $0.id == testID }) else {
            error = "Diesen Test kennt die App nicht."
            return false
        }
        guard test.maximalEffort else {
            error = "\(test.displayName) ist kein Test mit Vollbelastung. Das Tempo schätzt die App aus deinen Einheiten."
            return false
        }
        let values = test.evaluate(entries, definitions: module.performanceMetrics)
        let proposals = test.produces.compactMap { metric -> Proposal? in
            guard let value = values[metric],
                  let definition = registry.metricDefinition(metric, sport: sport),
                  definition.plausibleRange.contains(value) else { return nil }
            return Proposal(definition: definition, value: value, previous: current(metric, sport: sport))
        }
        guard !proposals.isEmpty else {
            error = "Aus diesen Angaben ergibt sich kein Wert. Prüf die Eingaben."
            return false
        }
        pending = PendingResult(sport: sport, testID: test.id, testName: test.displayName, measuredAt: measuredAt ?? now(), proposals: proposals)
        error = nil
        return true
    }

    /// Übernimmt das vorgelegte Ergebnis als getesteten Wert.
    @discardableResult
    public func accept() -> Bool {
        guard let pending else { return false }
        let values = pending.proposals.map {
            PerformanceValue(sport: pending.sport, metric: $0.definition.metric, value: $0.value, source: .tested, measuredAt: pending.measuredAt)
        }
        guard record(values) else { return false }
        self.pending = nil
        return true
    }

    /// Verwirft das vorgelegte Ergebnis; das Profil bleibt, wie es ist.
    public func discard() {
        pending = nil
    }

    /// Löscht alle bestätigten Werte; danach gelten wieder die Schätzungen.
    public func reset() {
        store.reset()
        profile = store.profile()
        pending = nil
        error = nil
    }

    private func record(_ values: [PerformanceValue]) -> Bool {
        var stored = true
        for value in values {
            stored = store.record(value) && stored
        }
        profile = store.profile()
        error = stored ? nil : "Der Wert konnte nicht gespeichert werden."
        return stored
    }
}

public extension AthleteStateSnapshot.PerformanceSummary {
    /// Alle Werte der Zusammenfassung als Leistungswerte, die für alle Sportarten ohne Sportart.
    var performanceValues: [PerformanceValue] {
        athlete.map { PerformanceValue(sport: nil, metric: $0.metric, value: $0.value, source: $0.source, measuredAt: $0.measuredAt) }
            + sports.flatMap { sport in
                sport.values.map { PerformanceValue(sport: sport.sport, metric: $0.metric, value: $0.value, source: $0.source, measuredAt: $0.measuredAt) }
            }
    }
}
