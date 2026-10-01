import Foundation

/// Die Uhrzeit, zu der der Tagesplan bereitliegen soll, und ob die Erinnerung an ist.
public struct ReminderSchedule: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var hour: Int
    public var minute: Int

    /// Standard: aus, 07:00 Uhr.
    public static let `default` = ReminderSchedule(isEnabled: false, hour: 7, minute: 0)

    /// So viele Tage im Voraus legt die App Benachrichtigungen an. Öffnest du die App eine Woche lang
    /// nicht, kommen sie trotzdem weiter, danach nicht mehr.
    public static let daysAhead = 7

    /// So lange vor der Uhrzeit startet die Vorbereitung im Hintergrund frühestens.
    public static let preparationLead: TimeInterval = 30 * 60

    public init(isEnabled: Bool, hour: Int, minute: Int) {
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Die nächsten Auslösezeitpunkte, einer pro Kalendertag, alle **nach** `now`. Leer, wenn aus.
    public func upcomingFireDates(from now: Date, days: Int = ReminderSchedule.daysAhead, calendar: Calendar = .current) -> [Date] {
        guard isEnabled, days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)

        return (0..<days).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime),
                  fire > now else { return nil }
            return fire
        }
    }

    /// Frühester Start der Hintergrundvorbereitung vor der nächsten Auslösung. Liegt der Zeitpunkt
    /// schon hinter uns (die Uhrzeit ist gleich), geht es in einer Minute los.
    public func nextPreparationDate(
        from now: Date,
        lead: TimeInterval = ReminderSchedule.preparationLead,
        calendar: Calendar = .current
    ) -> Date? {
        guard let next = upcomingFireDates(from: now, days: 2, calendar: calendar).first else { return nil }
        return max(next.addingTimeInterval(-lead), now.addingTimeInterval(60))
    }
}

/// Einstellung der täglichen Erinnerung, abgelegt in den UserDefaults.
@MainActor
public final class ReminderSettings: ObservableObject {
    static let storageKey = "reminder.schedule"

    @Published public var schedule: ReminderSchedule {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(ReminderSchedule.self, from: data) {
            self.schedule = stored
        } else {
            self.schedule = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(schedule) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// Titel und Text der Benachrichtigung.
public struct ReminderContent: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum ReminderContentBuilder {
    /// Liegt für den Tag der Benachrichtigung ein Plan vor, steht er im Text. Sonst ein Hinweis,
    /// die App zu öffnen (dann entsteht der Plan, das iPhone ist dann entsperrt).
    public static func content(for plan: PlanResponse?, on day: Date, calendar: Calendar = .current) -> ReminderContent {
        guard let plan, plan.date == PlanFormatting.isoDay(day, calendar: calendar) else {
            return ReminderContent(
                title: "Dein Trainingsplan für heute",
                body: "Öffne die App, dann erstellt Claude deinen Plan."
            )
        }

        if plan.plan.isRestDay {
            return ReminderContent(title: "Heute ist Ruhetag", body: "Erholung steht auf dem Plan. Die Begründung steht in der App.")
        }

        var parts = [
            PlanFormatting.sessionType(plan.plan.sessionType),
            PlanFormatting.meters(plan.plan.totalDistanceMeters),
            PlanFormatting.intensity(plan.plan.intensity)
        ]
        if plan.plan.estimatedDurationMinutes > 0 {
            parts.append("rund \(plan.plan.estimatedDurationMinutes) Minuten")
        }
        return ReminderContent(title: "Dein Plan für heute", body: parts.joined(separator: ", "))
    }
}
