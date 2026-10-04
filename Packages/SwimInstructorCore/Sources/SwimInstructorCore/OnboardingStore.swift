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

    /// Bis zum Abschluss nicht fertig, auch für alle, die die App schon vor P2 genutzt haben: Sie sehen die Einrichtung
    /// nach dem Update einmal, vorausgefüllt mit dem gespeicherten Ziel.
    public var isCompleted: Bool {
        defaults.bool(forKey: Self.storageKey)
    }

    public func complete() {
        defaults.set(true, forKey: Self.storageKey)
    }
}
