import Foundation

/// Speichert das Gesamtziel auf dem Gerät. Gibt es noch keins, gilt das bisher gespeicherte Schwimmziel
/// (`UserDefaultsGoalStore`, vor dem Triathlon-Umbau), sonst das Standardziel.
public protocol TrainingGoalStoring {
    func goal() -> TrainingGoal
    /// Speichert ein gültiges Ziel mit Zieltag nach `now`; sonst bleibt das alte und es kommt `false`.
    @discardableResult func setGoal(_ goal: TrainingGoal, now: Date) -> Bool
    /// Zurück zum Standardziel.
    func resetGoal()
}

public struct UserDefaultsTrainingGoalStore: TrainingGoalStoring {
    static let storageKey = "settings.trainingGoal"

    private let defaults: UserDefaults
    private let calendar: Calendar

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    public func goal() -> TrainingGoal {
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(TrainingGoal.self, from: data),
           stored.problem() == nil {
            return stored
        }
        // Umzug: das Schwimmziel aus den Einstellungen vor T2 (ungültig oder fehlend: das Standardziel).
        return TrainingGoal(legacy: UserDefaultsGoalStore(defaults: defaults).goal())
    }

    @discardableResult
    public func setGoal(_ goal: TrainingGoal, now: Date = Date()) -> Bool {
        guard goal.problem(now: now, calendar: calendar) == nil, let data = try? JSONEncoder().encode(goal) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    public func resetGoal() {
        defaults.removeObject(forKey: Self.storageKey)
        UserDefaultsGoalStore(defaults: defaults).resetGoal()
    }
}
