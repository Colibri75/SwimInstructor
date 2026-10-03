import Foundation

/// Speichert die bestätigten Leistungswerte (Tests, eigene Eingaben) mit Verlauf auf dem Gerät.
public protocol PerformanceProfileStoring {
    func profile() -> PerformanceProfile
    /// Speichert einen bestätigten Wert, den die Sportart kennt und der im plausiblen Bereich liegt; sonst `false`.
    @discardableResult func record(_ value: PerformanceValue) -> Bool
    /// Löscht alle Werte (zurück zu den Schätzungen).
    func reset()
}

public struct UserDefaultsPerformanceProfileStore: PerformanceProfileStoring {
    static let storageKey = "settings.performanceProfile"

    private let defaults: UserDefaults
    private let registry: SportRegistry

    public init(defaults: UserDefaults = .standard, registry: SportRegistry = .standard) {
        self.defaults = defaults
        self.registry = registry
    }

    public func profile() -> PerformanceProfile {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(PerformanceProfile.self, from: data) else { return .empty }
        return stored
    }

    @discardableResult
    public func record(_ value: PerformanceValue) -> Bool {
        guard value.source.isConfirmed,
              let definition = registry.metricDefinition(value.metric, sport: value.sport),
              definition.plausibleRange.contains(value.value),
              let data = try? JSONEncoder().encode(profile().recording(value)) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    public func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
