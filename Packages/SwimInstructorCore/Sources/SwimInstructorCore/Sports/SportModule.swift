import Foundation

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
    }

    /// In der Reihenfolge der Anmeldung (die App zeigt sie so an).
    public let modules: [any SportModule]

    public init(modules: [any SportModule]) throws {
        var seen = Set<SportID>()
        for module in modules {
            guard module.id.isWellFormed else { throw Problem.malformedID(module.id) }
            guard seen.insert(module.id).inserted else { throw Problem.duplicate(module.id) }
            guard !module.displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw Problem.missingDisplayName(module.id)
            }
            guard !module.symbolName.isEmpty else { throw Problem.missingSymbol(module.id) }
            guard !module.measures.isEmpty else { throw Problem.noMeasures(module.id) }
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
}
