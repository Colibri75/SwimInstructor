import Foundation

/// Merkt, wann der Wochenplan oder der Gesamtplan zuletzt automatisch angepasst wurde ("einmal am Tag").
/// Der Wert besteht aus dem Tag und einem Zusatz.
public protocol DailyRefreshMarking {
    func lastDay() -> String?
    func setLastDay(_ marker: String)
}

public struct UserDefaultsDailyRefreshMarker: DailyRefreshMarking {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String) {
        self.defaults = defaults
        self.key = key
    }

    public func lastDay() -> String? {
        defaults.string(forKey: key)
    }

    public func setLastDay(_ marker: String) {
        defaults.set(marker, forKey: key)
    }
}
