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
}

public extension SportModule {
    /// Ob ein Schritt mit diesem Maß und Ziel zu dieser Sportart passt (`nil` = ohne Ziel, immer erlaubt).
    func supports(measure: StepMeasure, target: StepTarget?) -> Bool {
        measures.contains(measure) && (target.map { targets.contains($0) } ?? true)
    }
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
            for rawValue in module.health.activityTypeRawValues {
                guard claimedActivityTypes.insert(rawValue).inserted else { throw Problem.sharedActivityType(module.id) }
            }
        }
        self.modules = modules
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

    /// Alle Workout-Arten aller Sportarten, für die Abfrage in Health.
    public var activityTypes: [HKWorkoutActivityType] {
        modules.flatMap(\.health.activityTypes)
    }

    /// Alle sportartspezifischen Messwerte, die die App in Health lesen darf.
    public var healthReadTypes: Set<HKObjectType> {
        modules.reduce(into: Set<HKObjectType>()) { $0.formUnion($1.health.readTypes) }
    }
}
