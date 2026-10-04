import Foundation
import HealthKit

/// Alles, was eine Sportart der App beibringt. Der Kern fragt nie "welche Sportart ist das?", sondern
/// immer das Modul: Eine neue Sportart ist ein neues Modul plus Tests, ohne Änderungen quer durch den Code.
///
/// Die Module wachsen mit jedem Schritt des Umbaus (Health, Belastung, Fortschritt, Statistik); hier stehen
/// zunächst die Angaben, die App und Server teilen.
public protocol SportModule: Sendable {
    var id: SportID { get }
    /// Deutscher Name für die Anzeige, z. B. "Schwimmen".
    var displayName: String { get }
    /// SF-Symbol für Listen und Karten.
    var symbolName: String { get }
    /// Maße, nach denen ein Schritt dieser Sportart geplant werden kann.
    var measures: Set<StepMeasure> { get }
    /// Ziele, nach denen sich die Intensität eines Schritts richten kann.
    var targets: Set<StepTarget> { get }
    /// Woran die Sportart in Health zu erkennen ist und welche Messwerte sie liest.
    var health: SportHealthMapping { get }
    /// Wie stark eine Minute dieser Sportart belastet, verglichen mit einer Minute Laufen (1,0). Rad belastet
    /// bei gleichem Puls weniger, weil das Körpergewicht getragen wird. Muss größer als 0 sein.
    var loadFactor: Double { get }
    /// Durchschnittstempo in m/s, das ein Wettkampfziel dieser Sportart haben darf (Strecke durch Zielzeit). Schützt
    /// vor Tippfehlern wie "10 km in 10 Minuten". Steht auch in `contracts/sports.json`, der Server prüft dasselbe.
    var goalSpeedRange: ClosedRange<Double> { get }

    // MARK: Planung (T4)

    /// Einheit, in der der Plan den Umfang dieser Sportart führt. Steht auch in `contracts/sports.json`.
    var planUnit: PlanUnit { get }
    /// Typisches Trainingstempo in m/s inklusive Pausen. Damit rechnet die App Meter und Minuten um, wenn der Athlet eine
    /// Einheit von Hand ändert oder die Sportart tauscht. Steht auch in `contracts/sports.json`, der Server rechnet ohne
    /// eigenes Tempo des Athleten mit demselben Wert.
    var typicalSpeedMetersPerSecond: Double { get }

    // MARK: Leistungsprofil (T2b)

    /// Leistungswerte dieser Sportart (z. B. CSS, Schwellenpuls). Die für alle Sportarten (Maximal-, Ruhepuls) stehen
    /// in `PerformanceMetricDefinition.athlete`. Steht auch in `contracts/sports.json`.
    var performanceMetrics: [PerformanceMetricDefinition] { get }
    /// Die Leistungstests dieser Sportart; jeder ermittelt Werte aus `performanceMetrics`.
    var performanceTests: [PerformanceTest] { get }
    /// Wie die Zonen der Ziele aus den Leistungswerten entstehen.
    var zoneSchemes: [ZoneScheme] { get }
    /// Startwerte ohne Test aus den Einheiten dieser Sportart und den schon bekannten Werten. Bestätigte Werte gehen
    /// später immer vor, die Schätzung muss sie nicht beachten.
    func estimatePerformance(_ context: PerformanceEstimationContext) -> [PerformanceEstimate]

    // MARK: Aufzeichnung auf der Watch (T5)

    /// Orte zur Auswahl vor dem Start und die Werte der Anzeige.
    var recording: SportRecording { get }

    // MARK: Statistik (T6)

    /// Die Kennzahlen dieser Sportart für die Kacheln, die wichtigste zuerst: Die ersten beiden erscheinen als
    /// Standard-Kacheln. Ohne eigene Liste leitet der Kern sie aus den Health-Angaben ab (`SportStatistics.derived`).
    var statistics: [StatisticDefinition] { get }
}

public extension SportModule {
    /// Ob ein Schritt mit diesem Maß und Ziel zu dieser Sportart passt (`nil` = ohne Ziel, immer erlaubt).
    func supports(measure: StepMeasure, target: StepTarget?) -> Bool {
        measures.contains(measure) && (target.map { targets.contains($0) } ?? true)
    }

    // Eine Sportart ohne Leistungsprofil plant nur nach gefühlter Anstrengung und Dauer.
    var performanceMetrics: [PerformanceMetricDefinition] { [] }
    var performanceTests: [PerformanceTest] { [] }
    var zoneSchemes: [ZoneScheme] { [] }
    func estimatePerformance(_ context: PerformanceEstimationContext) -> [PerformanceEstimate] { [] }

    // Ohne eigene Angaben zeichnet die Watch draußen mit GPS oder drinnen auf und zeigt Tempo und Strecke.
    var recording: SportRecording { .standard }

    var statistics: [StatisticDefinition] { SportStatistics.derived(for: self) }
}

/// Die angemeldeten Sportarten. Prüft beim Anlegen, dass jede Sportart vollständig beschrieben ist und keine
/// Kennung doppelt vorkommt.
public struct SportRegistry: Sendable {
    public enum Problem: Error, Equatable {
        case duplicate(SportID)
        case malformedID(SportID)
        case missingDisplayName(SportID)
        case missingSymbol(SportID)
        case noMeasures(SportID)
        case invalidLoadFactor(SportID)
        /// Zwei Sportarten beanspruchen dieselbe Workout-Art aus Health; die zweite wird genannt.
        case sharedActivityType(SportID)
        case invalidGoalSpeed(SportID)
        /// Ein Trainingstempo, mit dem sich Meter und Minuten nicht umrechnen lassen.
        case invalidTypicalSpeed(SportID)
        /// Ein Leistungswert ohne gültige Kennung, Namen, Einheit oder Bereich, doppelt oder einer für alle Sportarten.
        case invalidPerformanceMetric(SportID)
        /// Ein Test ohne gültige Kennung oder Dauer, doppelt oder mit einem Ergebnis, das die Sportart nicht kennt.
        case invalidPerformanceTest(SportID)
        /// Zonen für ein fremdes Ziel, aus einem unbekannten Grundwert oder mit ungültigen Grenzen.
        case invalidZoneScheme(SportID)
        /// Keine Orte für die Aufzeichnung, oder eine Kennung ungültig oder doppelt.
        case invalidRecording(SportID)
        /// Keine Kennzahlen für die Statistik, eine ohne gültige Kennung oder Namen, doppelt oder eine, die nicht aus
        /// den Einheiten rechnet (Tageswerte und Plan gibt es nur über alle Sportarten).
        case invalidStatistics(SportID)
    }

    /// In der Reihenfolge der Anmeldung (die App zeigt sie so an).
    public let modules: [any SportModule]

    public init(modules: [any SportModule]) throws {
        var seen = Set<SportID>()
        var claimedActivityTypes = Set<UInt>()
        for module in modules {
            guard module.id.isWellFormed else { throw Problem.malformedID(module.id) }
            guard seen.insert(module.id).inserted else { throw Problem.duplicate(module.id) }
            guard !module.displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw Problem.missingDisplayName(module.id)
            }
            guard !module.symbolName.isEmpty else { throw Problem.missingSymbol(module.id) }
            guard !module.measures.isEmpty else { throw Problem.noMeasures(module.id) }
            guard module.loadFactor > 0, module.loadFactor.isFinite else { throw Problem.invalidLoadFactor(module.id) }
            guard module.goalSpeedRange.lowerBound > 0, module.goalSpeedRange.upperBound.isFinite else {
                throw Problem.invalidGoalSpeed(module.id)
            }
            guard module.typicalSpeedMetersPerSecond > 0, module.typicalSpeedMetersPerSecond.isFinite else {
                throw Problem.invalidTypicalSpeed(module.id)
            }
            for rawValue in module.health.activityTypeRawValues {
                guard claimedActivityTypes.insert(rawValue).inserted else { throw Problem.sharedActivityType(module.id) }
            }
            try Self.validatePerformance(of: module)
            guard module.recording.isValid else { throw Problem.invalidRecording(module.id) }
            guard SportStatistics.isValid(module.statistics) else { throw Problem.invalidStatistics(module.id) }
        }
        self.modules = modules
    }

    private static func validatePerformance(of module: any SportModule) throws {
        let athleteMetrics = Set(PerformanceMetricDefinition.athlete.map(\.metric))
        var metrics = Set<PerformanceMetric>()
        for definition in module.performanceMetrics {
            guard definition.metric.isWellFormed,
                  !athleteMetrics.contains(definition.metric),
                  metrics.insert(definition.metric).inserted,
                  !definition.displayName.isEmpty,
                  !definition.unit.isEmpty,
                  definition.plausibleRange.lowerBound > 0,
                  definition.plausibleRange.upperBound.isFinite
            else { throw Problem.invalidPerformanceMetric(module.id) }
        }
        var testIDs = Set<String>()
        for test in module.performanceTests {
            guard SportID(rawValue: test.id).isWellFormed,
                  testIDs.insert(test.id).inserted,
                  !test.displayName.isEmpty,
                  !test.produces.isEmpty,
                  test.produces.allSatisfy({ metrics.contains($0) }),
                  test.durationMinutes > 0
            else { throw Problem.invalidPerformanceTest(module.id) }
        }
        for scheme in module.zoneSchemes {
            guard module.targets.contains(scheme.target),
                  metrics.contains(scheme.basis) || athleteMetrics.contains(scheme.basis),
                  scheme.hasValidBounds
            else { throw Problem.invalidZoneScheme(module.id) }
        }
    }

    /// Die Sportarten der App. `try!` ist hier sicher: `SportRegistryTests` und `ContractTests` legen genau diese
    /// Registry an und prüfen sie gegen `contracts/sports.json`, eine ungültige Liste kommt nie über die CI hinaus.
    public static let standard: SportRegistry = try! SportRegistry(modules: [SwimModule(), BikeModule(), RunModule()])

    public var ids: [SportID] { modules.map(\.id) }

    /// `nil` für eine Kennung, die diese App-Version nicht kennt.
    public func module(for id: SportID) -> (any SportModule)? {
        modules.first { $0.id == id }
    }

    /// Name für die Anzeige, auch für eine Kennung, die diese App-Version nicht kennt (dann die Kennung selbst).
    public func displayName(for id: SportID) -> String {
        module(for: id)?.displayName ?? id.rawValue
    }

    /// SF-Symbol für die Anzeige, mit neutralem Symbol für unbekannte Kennungen.
    public func symbolName(for id: SportID) -> String {
        module(for: id)?.symbolName ?? "figure.mixed.cardio"
    }

    /// Ob eine Strecke in dieser Zielzeit für die Sportart ein plausibles Durchschnittstempo ergibt.
    public func isPlausibleGoal(sport: SportID, distanceMeters: Double, durationSeconds: TimeInterval) -> Bool {
        guard let module = module(for: sport), durationSeconds > 0 else { return false }
        return module.goalSpeedRange.contains(distanceMeters / durationSeconds)
    }

    /// Die Sportart, zu der ein Health-Workout dieser Art gehört; `nil` für Arten, die keine Sportart kennt.
    public func module(forActivityType activityType: HKWorkoutActivityType) -> (any SportModule)? {
        modules.first { $0.health.activityTypeRawValues.contains(activityType.rawValue) }
    }

    /// Was ein Leistungswert bedeutet (`sport == nil`: einer für alle Sportarten); `nil` für unbekannte Werte.
    public func metricDefinition(_ metric: PerformanceMetric, sport: SportID?) -> PerformanceMetricDefinition? {
        guard let sport else { return PerformanceMetricDefinition.athlete.first { $0.metric == metric } }
        return module(for: sport)?.performanceMetrics.first { $0.metric == metric }
    }

    /// Alle Workout-Arten aller Sportarten, für die Abfrage in Health.
    public var activityTypes: [HKWorkoutActivityType] {
        modules.flatMap(\.health.activityTypes)
    }

    /// Alle sportartspezifischen Messwerte, die die App in Health lesen darf.
    public var healthReadTypes: Set<HKObjectType> {
        modules.reduce(into: Set<HKObjectType>()) { $0.formUnion($1.health.readTypes) }
    }
}
