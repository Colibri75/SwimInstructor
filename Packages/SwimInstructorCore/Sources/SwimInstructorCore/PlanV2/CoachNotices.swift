import Foundation

/// Eine Mitteilung des Coachs auf dem iPhone: Text und Kennung, unter der sie nur einmal (oder ersetzend) erscheint.
public struct CoachNotice: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

/// Was der Coach von sich aus meldet: morgens den fertigen Plan für den Tag, nach einer Einheit "Wie war's?".
public enum CoachNotices {
    /// Kennung der Morgen-Mitteilung: eine je Tag, eine neue Vorschau ersetzt die alte.
    public static func morningID(for date: String) -> String { "morning-plan-\(date)" }

    /// Kennung der Frage nach einer Einheit: eine je Einheit.
    public static func feedbackID(for workoutID: UUID) -> String { "feedback-\(workoutID.uuidString)" }

    /// "Dein Plan für heute steht" mit den Einheiten des Tags, `nil` an einem Tag ohne Einheiten und Blöcke.
    public static func morningPlan(_ plan: DayPlanV2Response, registry: SportRegistry = .standard) -> CoachNotice? {
        guard let summary = planSummary(plan.plan, registry: registry) else { return nil }
        return CoachNotice(id: morningID(for: plan.date), title: "Dein Plan für heute steht", body: summary)
    }

    /// "Laufen · 40 min, Kraft", in der Reihenfolge des Plans; `nil` ohne Einheiten und Blöcke.
    public static func planSummary(_ plan: DayPlanV2, registry: SportRegistry = .standard) -> String? {
        let sessions = plan.sessions.map { PlanV2Formatting.sessionTitle(sport: $0.sport, amount: $0.amount, unit: $0.unit, registry: registry) }
        let extras = plan.extras.map(\.kind.displayName)
        let parts = sessions + extras
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "Wie war's?" nach einer Einheit aus Health.
    public static func feedback(for workout: Workout, registry: SportRegistry = .standard) -> CoachNotice {
        let minutes = Int((workout.duration / 60).rounded())
        return CoachNotice(
            id: feedbackID(for: workout.id),
            title: "Wie war's?",
            body: "\(registry.displayName(for: workout.sport)), \(minutes) min. Sag deinem Coach, wie anstrengend es war und ob etwas wehtut."
        )
    }

    /// Wann die Morgen-Mitteilung für `date` (`yyyy-MM-dd`) kommt: zur eingestellten Uhrzeit, `nil` wenn die schon vorbei ist.
    public static func morningDate(for date: String, preferences: NotificationPreferences, now: Date, calendar: Calendar = .current) -> Date? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        components.hour = preferences.morningHour
        components.minute = preferences.morningMinute
        guard let fire = calendar.date(from: components), fire > now else { return nil }
        return fire
    }
}

/// Welche Mitteilungen der Coach schicken darf und wann morgens.
public struct NotificationPreferences: Codable, Equatable, Sendable {
    /// Morgens: "Dein Plan für heute steht", sobald der Plan vorab fertig ist.
    public var morningPlan: Bool
    /// Nach einer Einheit: "Wie war's?".
    public var afterWorkout: Bool
    public var morningHour: Int
    public var morningMinute: Int

    public init(morningPlan: Bool = true, afterWorkout: Bool = true, morningHour: Int = 7, morningMinute: Int = 0) {
        self.morningPlan = morningPlan
        self.afterWorkout = afterWorkout
        self.morningHour = min(max(morningHour, 0), 23)
        self.morningMinute = min(max(morningMinute, 0), 59)
    }

    public static let standard = NotificationPreferences()
}

public protocol NotificationPreferencesStoring {
    func preferences() -> NotificationPreferences
    func save(_ preferences: NotificationPreferences)
}

public struct UserDefaultsNotificationPreferencesStore: NotificationPreferencesStoring {
    static let storageKey = "settings.notifications"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func preferences() -> NotificationPreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else { return .standard }
        return stored
    }

    public func save(_ preferences: NotificationPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Welche Mitteilungen schon gekommen sind, damit dieselbe Einheit nicht zweimal nachfragt.
public protocol NoticeLogging {
    func wasSent(_ id: String) -> Bool
    func markSent(_ id: String)
}

public struct UserDefaultsNoticeLog: NoticeLogging {
    static let storageKey = "notifications.sent"
    /// So viele Kennungen bleiben gespeichert.
    static let keep = 60

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func wasSent(_ id: String) -> Bool {
        (defaults.stringArray(forKey: Self.storageKey) ?? []).contains(id)
    }

    public func markSent(_ id: String) {
        var ids = (defaults.stringArray(forKey: Self.storageKey) ?? []).filter { $0 != id }
        ids.append(id)
        defaults.set(Array(ids.suffix(Self.keep)), forKey: Self.storageKey)
    }
}
