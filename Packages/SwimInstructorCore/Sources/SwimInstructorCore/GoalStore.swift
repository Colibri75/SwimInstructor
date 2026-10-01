import Foundation

/// Das Gesamtziel des Athleten (Distanz, Zielzeit, Zieltag). Es bleibt auf dem Gerät gespeichert, bis es
/// geändert wird, und geht mit jeder Plananfrage im Snapshot zum Server (und damit in den Prompt).
public protocol AthleteGoalStoring {
    /// Das gespeicherte Ziel; ohne gültiges gespeichertes Ziel das Standardziel.
    func goal() -> AthleteGoal
    /// Speichert ein gültiges Ziel; ein ungültiges (`problem != nil`) wird nicht gespeichert.
    @discardableResult func setGoal(_ goal: AthleteGoal) -> Bool
    /// Zurück zum Standardziel.
    func resetGoal()
}

public struct UserDefaultsGoalStore: AthleteGoalStoring {
    static let storageKey = "settings.goal"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func goal() -> AthleteGoal {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(AthleteGoal.self, from: data),
              stored.problem == nil else {
            return .default
        }
        return stored
    }

    @discardableResult
    public func setGoal(_ goal: AthleteGoal) -> Bool {
        guard goal.problem == nil, let data = try? JSONEncoder().encode(goal) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    public func resetGoal() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
