import Foundation

/// Hilfsmittel, die ein Plan verlangen kann. Die Rohwerte sind die des Servers (`equipment`).
public enum EquipmentItem: String, CaseIterable, Identifiable, Sendable {
    case pullBuoy = "pull_buoy"
    case paddles
    case fins
    case snorkel
    case kickboard
    case ankleBand = "ankle_band"

    public var id: String { rawValue }

    /// Deutscher Name, derselbe wie in der Plananzeige.
    public var title: String { PlanFormatting.equipmentName(rawValue) }
}

/// Welche Hilfsmittel der Athlet hat (Einstellungen). Noch nichts gewählt: alle, damit sich für
/// bestehende Nutzer nichts ändert. Die Auswahl geht mit jeder Plananfrage zum Server, Claude plant
/// dann nur damit und die Sicherheitsschicht entfernt alles andere.
public protocol OwnedEquipmentStoring {
    /// Rohwerte (`pull_buoy`, …) der vorhandenen Hilfsmittel in fester Reihenfolge; leer heißt "keins".
    func ownedEquipment() -> [String]
    func setOwnedEquipment(_ items: Set<EquipmentItem>)
}

public struct UserDefaultsOwnedEquipmentStore: OwnedEquipmentStoring {
    static let storageKey = "settings.ownedEquipment"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func ownedEquipment() -> [String] {
        guard let stored = defaults.array(forKey: Self.storageKey) as? [String] else {
            return EquipmentItem.allCases.map(\.rawValue)
        }
        // Feste Reihenfolge, Unbekanntes (etwa aus einer späteren Version) fällt weg.
        return EquipmentItem.allCases.map(\.rawValue).filter(stored.contains)
    }

    public func setOwnedEquipment(_ items: Set<EquipmentItem>) {
        defaults.set(EquipmentItem.allCases.filter(items.contains).map(\.rawValue), forKey: Self.storageKey)
    }
}

/// Hilfsmittel und Orte aus den Sportmodulen: womit eine Sportart drinnen geht (Rolle, Laufband) und Zugang zu Freiwasser.
/// Anders als beim Schwimm-Equipment ist ohne Auswahl nichts da: Erst damit plant der Server drinnen oder im Freiwasser.
public protocol IndoorEquipmentStoring {
    /// Kennungen (`indoor_trainer`, `open_water`, …) in der Reihenfolge der Sportarten.
    func ownedIndoorEquipment() -> [String]
    func setOwnedIndoorEquipment(_ ids: Set<String>)
}

public struct UserDefaultsIndoorEquipmentStore: IndoorEquipmentStoring {
    static let storageKey = "settings.indoorEquipment"

    private let defaults: UserDefaults
    private let registry: SportRegistry

    public init(defaults: UserDefaults = .standard, registry: SportRegistry = .standard) {
        self.defaults = defaults
        self.registry = registry
    }

    public func ownedIndoorEquipment() -> [String] {
        let stored = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
        return registry.venueIDs.filter(stored.contains)
    }

    public func setOwnedIndoorEquipment(_ ids: Set<String>) {
        defaults.set(registry.venueIDs.filter(ids.contains), forKey: Self.storageKey)
    }
}

public extension SportRegistry {
    /// Die Hilfsmittel für drinnen über alle Sportarten, ohne Doppelte, in der Reihenfolge der Sportarten.
    var indoorEquipment: [IndoorEquipment] {
        var seen = Set<String>()
        return modules.compactMap(\.indoorEquipment).filter { seen.insert($0.id).inserted }
    }

    /// Freiwasser über alle Sportarten, ohne Doppelte.
    var openWaterVenues: [OpenWaterVenue] {
        var seen = Set<String>()
        return modules.compactMap(\.openWater).filter { seen.insert($0.id).inserted }
    }

    /// Alle Kennungen für drinnen und Freiwasser, wie sie gespeichert werden und zum Server gehen.
    var venueIDs: [String] {
        indoorEquipment.map(\.id) + openWaterVenues.map(\.id)
    }
}
