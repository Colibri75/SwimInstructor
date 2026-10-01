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
