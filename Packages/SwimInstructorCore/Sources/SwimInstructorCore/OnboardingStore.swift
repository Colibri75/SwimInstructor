import Foundation

/// Merkt sich, ob die Einrichtung beim ersten Start (P2: Ziel, Wochenraster, Startniveau) fertig ist.
public protocol OnboardingStoring {
    var isCompleted: Bool { get }
    func complete()
}

public struct UserDefaultsOnboardingStore: OnboardingStoring {
    static let storageKey = "onboarding.completed"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Beim ersten Lesen nach dem Update gilt die Einrichtung als fertig, wenn schon ein Ziel gespeichert ist (auch das
    /// Schwimmziel von vor T2): Wer die App schon nutzt, bekommt sie nicht noch einmal. Das Ergebnis wird sofort
    /// gespeichert, damit ein Ziel, das erst während der Einrichtung entsteht, sie nicht überspringt.
    public var isCompleted: Bool {
        if defaults.object(forKey: Self.storageKey) == nil {
            let existing = defaults.data(forKey: UserDefaultsTrainingGoalStore.storageKey) != nil
                || defaults.data(forKey: UserDefaultsGoalStore.storageKey) != nil
            defaults.set(existing, forKey: Self.storageKey)
        }
        return defaults.bool(forKey: Self.storageKey)
    }

    public func complete() {
        defaults.set(true, forKey: Self.storageKey)
    }
}
