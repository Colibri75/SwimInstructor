import EventKit
import SwimInstructorCore

/// Freie Zeit je Tag aus dem Kalender: der längste freie Block im Trainingsfenster. Liest nur Beginn, Ende und
/// "belegt" der Termine, keine Titel; nichts davon verlässt das Gerät außer der Zahl der freien Minuten.
@MainActor
final class CalendarAvailabilityProvider: ObservableObject {
    @Published private(set) var isAuthorized: Bool
    @Published private(set) var isDenied = false

    private let store = EKEventStore()
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.isAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Fragt nach dem Zugriff (nur einmal sichtbar, danach entscheidet die Einstellung des Systems).
    func requestAccess() async {
        do {
            isAuthorized = try await store.requestFullAccessToEvents()
        } catch {
            isAuthorized = false
        }
        isDenied = !isAuthorized
    }

    /// Freie Minuten für die Tage `dates` (`yyyy-MM-dd`) zwischen `startHour` und `endHour`. Ohne Zugriff: keine Angabe.
    func availability(for dates: [String], startHour: Int, endHour: Int) -> [DayAvailability] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let weekCalendar = WeekCalendar(calendar: calendar)
        return dates.compactMap { key in
            guard let day = weekCalendar.date(from: key) else { return nil }
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let busy = store.events(matching: predicate)
                // Ganztägige Einträge (Geburtstage, Urlaub, Feiertage) blockieren nur, wenn sie als belegt markiert sind.
                .filter { $0.availability != .free && !($0.isAllDay && $0.availability != .busy && $0.availability != .unavailable) }
                .map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)) }
            return DayAvailability(
                date: key,
                minutes: CalendarAvailability.freeMinutes(busy: busy, day: day, startHour: startHour, endHour: endHour, calendar: calendar)
            )
        }
    }
}
