import Foundation

/// Speichert das Gesamtziel auf dem Gerät. Gibt es noch keins, gilt das Standardziel.
public protocol TrainingGoalStoring {
    func goal() -> TrainingGoal
    /// Speichert ein gültiges Ziel mit Zieltag nach `now`; sonst bleibt das alte und es kommt `false`.
    @discardableResult func setGoal(_ goal: TrainingGoal, now: Date) -> Bool
    /// Zurück zum Standardziel.
    func resetGoal()

    // MARK: Zieländerung mit Entwurf (P3)

    /// Zählt neue Ziele hoch; ein Gesamtplan gehört zu genau einer Version.
    var goalVersion: Int { get }
    /// Bis wann ein neues Ziel gesperrt ist; `nil`, wenn es jetzt übernommen werden kann.
    func lockedUntil(now: Date) -> Date?
    /// Übernimmt einen Entwurf aus dem Ziel-Editor: Feinjustierung sofort, ein neues Ziel nur ohne Sperre (dann mit neuer
    /// Version und neuer Sperre). Ein übernommenes Ziel ersetzt einen vorgemerkten Entwurf.
    @discardableResult func apply(_ goal: TrainingGoal, now: Date) -> GoalApplyResult
    /// Der vorgemerkte Entwurf, der beim Ende der Sperre übernommen wird.
    func pendingGoal() -> TrainingGoal?
    func setPendingGoal(_ goal: TrainingGoal?)
    /// Übernimmt den vorgemerkten Entwurf, sobald die Sperre vorbei ist; `true`, wenn er übernommen wurde.
    @discardableResult func applyPendingIfDue(now: Date) -> Bool
}

public struct UserDefaultsTrainingGoalStore: TrainingGoalStoring {
    static let storageKey = "settings.trainingGoal"
    static let versionKey = "settings.trainingGoal.version"
    static let appliedAtKey = "settings.trainingGoal.appliedAt"
    static let pendingKey = "settings.trainingGoal.pending"
    /// Höchstens ein neues Ziel in so vielen Tagen.
    public static let lockDays = 7

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
        return .default
    }

    /// Speichert ohne Sperre (Einrichtung beim ersten Start). Ein neues Ziel bekommt trotzdem eine neue Version.
    @discardableResult
    public func setGoal(_ goal: TrainingGoal, now: Date = Date()) -> Bool {
        guard goal.problem(now: now, calendar: calendar) == nil, let data = try? JSONEncoder().encode(goal) else { return false }
        if self.goal().change(to: goal, calendar: calendar) == .newGoal {
            defaults.set(goalVersion + 1, forKey: Self.versionKey)
        }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    public func resetGoal() {
        defaults.removeObject(forKey: Self.storageKey)
        defaults.set(goalVersion + 1, forKey: Self.versionKey)
        defaults.removeObject(forKey: Self.pendingKey)
    }

    // MARK: - Zieländerung mit Entwurf

    public var goalVersion: Int {
        max(defaults.integer(forKey: Self.versionKey), 1)
    }

    public func lockedUntil(now: Date) -> Date? {
        guard let appliedAt = defaults.object(forKey: Self.appliedAtKey) as? Date else { return nil }
        // Ist der Zieltag vorbei, geht ein neues Ziel sofort.
        guard calendar.startOfDay(for: goal().targetDate) >= calendar.startOfDay(for: now) else { return nil }
        guard let end = calendar.date(byAdding: .day, value: Self.lockDays, to: appliedAt), end > now else { return nil }
        return end
    }

    @discardableResult
    public func apply(_ goal: TrainingGoal, now: Date) -> GoalApplyResult {
        if let problem = goal.problem(now: now, calendar: calendar) { return .invalid(problem) }
        let change = self.goal().change(to: goal, calendar: calendar)
        if change == .newGoal, let until = lockedUntil(now: now) { return .locked(until: until) }
        guard let data = try? JSONEncoder().encode(goal) else { return .invalid("Das Ziel lässt sich nicht speichern.") }
        defaults.set(data, forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.pendingKey)
        switch change {
        case .none:
            return .unchanged
        case .fineTuning:
            return .fineTuned
        case .newGoal:
            defaults.set(goalVersion + 1, forKey: Self.versionKey)
            defaults.set(now, forKey: Self.appliedAtKey)
            return .newGoal
        }
    }

    public func pendingGoal() -> TrainingGoal? {
        guard let data = defaults.data(forKey: Self.pendingKey) else { return nil }
        return try? JSONDecoder().decode(TrainingGoal.self, from: data)
    }

    public func setPendingGoal(_ goal: TrainingGoal?) {
        guard let goal, let data = try? JSONEncoder().encode(goal) else {
            defaults.removeObject(forKey: Self.pendingKey)
            return
        }
        defaults.set(data, forKey: Self.pendingKey)
    }

    @discardableResult
    public func applyPendingIfDue(now: Date) -> Bool {
        guard let pending = pendingGoal() else { return false }
        switch apply(pending, now: now) {
        case .locked:
            return false
        case .invalid:
            // Zum Beispiel ist der Zieltag des Entwurfs inzwischen vorbei: Er verfällt.
            setPendingGoal(nil)
            return false
        case .unchanged:
            return false
        case .fineTuned, .newGoal:
            return true
        }
    }
}
