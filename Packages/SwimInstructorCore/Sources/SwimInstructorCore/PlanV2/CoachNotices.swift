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

    /// Ob eine Mitteilung die Frage nach einer Einheit ist.
    public static func isFeedbackID(_ id: String) -> Bool { id.hasPrefix("feedback-") }

    /// So lange nach dem Ende einer Einheit kommt "Wie war's?" frühestens: Die Bewertung auf der Watch landet erst nach
    /// dem Workout in Health. Wer dort schon bewertet hat, bekommt keine Frage mehr.
    public static let feedbackDelay: TimeInterval = 10 * 60

    /// Wie lange die Frage nach einer Einheit, die `end` zu Ende ging, ab `now` noch wartet (mindestens eine Sekunde).
    public static func feedbackDelay(after end: Date, now: Date) -> TimeInterval {
        max(feedbackDelay - now.timeIntervalSince(end), 1)
    }

    /// "Dein Plan für heute steht" mit den Einheiten des Tags, `nil` an einem Tag ohne Einheiten und Blöcke.
    public static func morningPlan(_ plan: DayPlanV2Response, registry: SportRegistry = .standard) -> CoachNotice? {
        guard let summary = planSummary(plan.plan, registry: registry) else { return nil }
        return CoachNotice(id: morningID(for: plan.date), title: String(localized: "Dein Plan für heute steht"), body: summary)
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
        let sportName: String = registry.displayName(for: workout.sport)
        return CoachNotice(
            id: feedbackID(for: workout.id),
            title: String(localized: "Wie war's?"),
            body: String(localized: "\(sportName), \(minutes) min. Sag deinem Coach, wie anstrengend es war und ob etwas wehtut.")
        )
    }

    /// Kennung der Mitteilung zu einer angepassten Planung: eine je Tag, eine neuere ersetzt die ältere.
    public static func planChangedID(for date: String) -> String { "plan-changed-\(date)" }

    /// "Dein Coach hat deinen Plan angepasst": der Anlass, sonst der erste geänderte Tag. `nil`, wenn es nichts zu
    /// melden gibt (`PlanChangeReport.isWorthTelling`).
    public static func planChanged(_ report: PlanChangeReport, on date: String, calendar: WeekCalendar = WeekCalendar()) -> CoachNotice? {
        guard report.isWorthTelling else { return nil }
        let body: String
        if let notice = PlanV2Formatting.adaptationNotice(report.reason) {
            body = notice
        } else if let first = report.changes.first {
            let day = calendar.weekdayName(first.date)
            let after = first.after
            let before = first.before
            let more = report.changes.count - 1
            switch more {
            case 0: body = String(localized: "\(day): jetzt \(after) statt \(before).")
            case 1: body = String(localized: "\(day): jetzt \(after) statt \(before). Dazu ein weiterer Tag.")
            default: body = String(localized: "\(day): jetzt \(after) statt \(before). Dazu \(more) weitere Tage.")
            }
        } else {
            return nil
        }
        return CoachNotice(id: planChangedID(for: date), title: String(localized: "Dein Coach hat deinen Plan angepasst"), body: body)
    }

    /// Die ganze Nachricht hinter der Mitteilung: Anlass, jeder geänderte Tag mit vorher und jetzt, die Begründung.
    public static func planChangedMessage(_ report: PlanChangeReport, notice: CoachNotice, at date: Date, calendar: WeekCalendar = WeekCalendar()) -> CoachMessage {
        let reason = PlanV2Formatting.adaptationNotice(report.reason)
            ?? String(localized: "Dein Coach stimmt die nächsten 14 Tage jeden Morgen auf deinen aktuellen Zustand, dein Training und deinen Gesamtplan ab.")
        let details = report.changes.map { change in
            let day = "\(calendar.weekdayName(change.date)), \(PlanFormatting.shortGermanDate(change.date))"
            let after = change.after
            let before = change.before
            return String(localized: "\(day): jetzt \(after), vorher \(before)")
        }
        return CoachMessage(
            id: notice.id, kind: .planChanged, date: date, title: notice.title, body: reason,
            details: details, rationale: report.rationale.isEmpty ? nil : report.rationale
        )
    }

    /// Kennung der Wochenbilanz: eine je Woche (Montag der neuen Woche).
    public static func weeklyCourseID(for weekStart: String) -> String { "weekly-course-\(weekStart)" }

    /// Die Wochenbilanz am Montag: "Wochenbilanz: Auf Kurs" und der Satz zum Stand. `nil`, solange es noch keine volle
    /// Woche mit Plan gibt.
    public static func weeklyCourse(_ course: GoalCourse, weekStart: String, registry: SportRegistry = .standard) -> CoachNotice? {
        guard course.status != .noData, course.percent != nil else { return nil }
        let status = course.status.title
        return CoachNotice(
            id: weeklyCourseID(for: weekStart),
            title: String(localized: "Wochenbilanz: \(status)"),
            body: course.sentence(registry: registry)
        )
    }

    /// Kennung der Mitteilung nach einer Fortschreibung des Gesamtplans.
    public static func macroReviewID(for weekStart: String) -> String { "macro-review-\(weekStart)" }

    /// Die Nachricht zu einer Fortschreibung: Bilanz, Änderungen und Hinweise deines Coachs.
    public static func macroReviewMessage(_ review: MacroReview, at date: Date) -> CoachMessage {
        let summary = review.summary.isEmpty ? review.reason.title : review.summary
        return CoachMessage(
            id: macroReviewID(for: review.weekStart), kind: .macroReview, date: date,
            title: String(localized: "Gesamtplan fortgeschrieben"), body: summary,
            details: review.changes + review.adjustments, rationale: review.feedback
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
    /// Hat dein Coach die nächsten Tage im Hintergrund spürbar geändert: was und warum.
    public var planChanges: Bool
    /// Montags: ob du auf Kurs zum Ziel bist.
    public var weeklyCourse: Bool
    public var morningHour: Int
    public var morningMinute: Int

    public init(morningPlan: Bool = true, afterWorkout: Bool = true, planChanges: Bool = true, weeklyCourse: Bool = true, morningHour: Int = 7, morningMinute: Int = 0) {
        self.morningPlan = morningPlan
        self.afterWorkout = afterWorkout
        self.planChanges = planChanges
        self.weeklyCourse = weeklyCourse
        self.morningHour = min(max(morningHour, 0), 23)
        self.morningMinute = min(max(morningMinute, 0), 59)
    }

    /// Gespeichertes von früher kennt nicht jeden Schalter: Fehlende gelten als an, die übrigen bleiben.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = NotificationPreferences.standard
        self.init(
            morningPlan: try container.decodeIfPresent(Bool.self, forKey: .morningPlan) ?? standard.morningPlan,
            afterWorkout: try container.decodeIfPresent(Bool.self, forKey: .afterWorkout) ?? standard.afterWorkout,
            planChanges: try container.decodeIfPresent(Bool.self, forKey: .planChanges) ?? standard.planChanges,
            weeklyCourse: try container.decodeIfPresent(Bool.self, forKey: .weeklyCourse) ?? standard.weeklyCourse,
            morningHour: try container.decodeIfPresent(Int.self, forKey: .morningHour) ?? standard.morningHour,
            morningMinute: try container.decodeIfPresent(Int.self, forKey: .morningMinute) ?? standard.morningMinute
        )
    }

    private enum CodingKeys: String, CodingKey {
        case morningPlan, afterWorkout, planChanges, weeklyCourse, morningHour, morningMinute
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

// MARK: - Antippen

/// Wohin eine Mitteilung beim Antippen führt. Reist im `userInfo` der Mitteilung mit.
public enum NotificationRoute: Equatable, Sendable {
    /// Aktuell (Plan für heute).
    case today
    /// "Wie war's?" für die Einheit mit diesem Anfang und Ende.
    case feedback(start: Date, end: Date)
    /// Eine gespeicherte Nachricht deines Coachs ganz zeigen (`CoachMessageStoring`).
    case message(id: String)
    /// "Weg zum Ziel": ob du auf Kurs bist (Wochenbilanz).
    case course

    public static let routeKey = "route"
    public static let workoutStartKey = "workoutStart"
    public static let workoutEndKey = "workoutEnd"
    public static let messageKey = "messageID"

    /// Für `UNMutableNotificationContent.userInfo`.
    public var userInfo: [String: Any] {
        switch self {
        case .today:
            return [Self.routeKey: "today"]
        case let .feedback(start, end):
            return [Self.routeKey: "feedback", Self.workoutStartKey: start.timeIntervalSince1970, Self.workoutEndKey: end.timeIntervalSince1970]
        case let .message(id):
            return [Self.routeKey: "message", Self.messageKey: id]
        case .course:
            return [Self.routeKey: "course"]
        }
    }

    /// Liest die Route einer Mitteilung. Mitteilungen von vor dieser Version tragen keine; sie führen nach ihrer
    /// Kennung: "Wie war's?" zur Einheit, der Plan am Morgen nach Aktuell, eine Fortschreibung zu ihrer Nachricht.
    public init?(identifier: String, userInfo: [AnyHashable: Any]) {
        let start = (userInfo[Self.workoutStartKey] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        let end = (userInfo[Self.workoutEndKey] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        switch userInfo[Self.routeKey] as? String {
        case "today":
            self = .today
        case "feedback":
            guard let start, let end else { return nil }
            self = .feedback(start: start, end: end)
        case "message":
            guard let id = userInfo[Self.messageKey] as? String else { return nil }
            self = .message(id: id)
        case "course":
            self = .course
        default:
            if CoachNotices.isFeedbackID(identifier), let start, let end {
                self = .feedback(start: start, end: end)
            } else if identifier.hasPrefix("macro-review-") || identifier.hasPrefix("plan-changed-") {
                self = .message(id: identifier)
            } else if identifier.hasPrefix("morning-plan-") {
                self = .today
            } else {
                return nil
            }
        }
    }
}

// MARK: - Nachrichten

/// Eine Nachricht deines Coachs, ganz: Die Mitteilung zeigt nur den Anfang, die App den Rest.
public struct CoachMessage: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Die nächsten Tage sind neu abgestimmt.
        case planChanged
        /// Der Gesamtplan ist fortgeschrieben.
        case macroReview
    }

    /// Dieselbe Kennung wie die Mitteilung.
    public let id: String
    public let kind: Kind
    public let date: Date
    public let title: String
    public let body: String
    /// Die einzelnen Änderungen, je eine Zeile.
    public let details: [String]
    /// Begründung oder Einschätzung deines Coachs.
    public let rationale: String?

    public init(id: String, kind: Kind, date: Date, title: String, body: String, details: [String] = [], rationale: String? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.body = body
        self.details = details
        self.rationale = rationale
    }
}

public protocol CoachMessageStoring {
    /// Neueste zuerst.
    func messages() -> [CoachMessage]
    func message(id: String) -> CoachMessage?
    /// Ersetzt eine Nachricht mit derselben Kennung.
    func save(_ message: CoachMessage)
}

public struct UserDefaultsCoachMessageStore: CoachMessageStoring {
    static let storageKey = "notifications.messages"
    /// So viele Nachrichten bleiben gespeichert.
    static let keep = 30

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func messages() -> [CoachMessage] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode([CoachMessage].self, from: data) else { return [] }
        return stored.sorted { $0.date > $1.date }
    }

    public func message(id: String) -> CoachMessage? {
        messages().first { $0.id == id }
    }

    public func save(_ message: CoachMessage) {
        let updated = Array(([message] + messages().filter { $0.id != message.id }).prefix(Self.keep))
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
