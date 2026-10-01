import Foundation

public enum DailyWish {
    /// So lang darf der Wunsch höchstens sein (der Server nimmt bis 500 Zeichen).
    public static let maxLength = 300
    /// So viele Tage hebt die App Wünsche auf, ältere werden gelöscht.
    public static let retainedDays = 14
}

/// Der Wunsch des Athleten für einen Tag (z. B. "Heute lieber Technik, Schulter zwickt").
/// Er gilt nur für diesen Kalendertag: Morgen beginnt wieder ohne Wunsch.
public protocol DailyWishStoring {
    /// `day` ist der Tag als `yyyy-MM-dd`. `nil`, wenn kein Wunsch hinterlegt ist.
    func wish(for day: String) -> String?
    /// Leerer Text oder `nil` löscht den Wunsch dieses Tages.
    func setWish(_ text: String?, for day: String)
}

public struct UserDefaultsDailyWishStore: DailyWishStoring {
    static let storageKey = "plan.dailyWishes"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func wish(for day: String) -> String? {
        stored()[day]
    }

    public func setWish(_ text: String?, for day: String) {
        var wishes = stored()
        let cleaned = String((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(DailyWish.maxLength))
        if cleaned.isEmpty {
            wishes.removeValue(forKey: day)
        } else {
            wishes[day] = cleaned
        }
        // Die Schlüssel sind ISO-Tage, alphabetisch gleich zeitlich: nur die neuesten behalten.
        for key in wishes.keys.sorted(by: >).dropFirst(DailyWish.retainedDays) {
            wishes.removeValue(forKey: key)
        }
        defaults.set(wishes, forKey: Self.storageKey)
    }

    private func stored() -> [String: String] {
        defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
    }
}
