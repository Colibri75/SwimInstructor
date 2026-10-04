import Foundation

/// Rechnen mit Kalendertagen im Format `yyyy-MM-dd` und Wochen von Montag bis Sonntag. Die Wochen
/// laufen unabhängig von der Spracheinstellung des Geräts ab Montag.
public struct WeekCalendar: Sendable {
    private static let shortNames = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    private static let longNames = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Mittag des Tages (Mittag bleibt bei Zeitumstellungen derselbe Kalendertag).
    public func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    public func key(for date: Date) -> String {
        PlanFormatting.isoDay(date, calendar: calendar)
    }

    /// Der Montag der Woche, in der `date` liegt.
    public func weekStart(containing date: Date) -> String {
        key(for: weekStartDate(containing: date))
    }

    /// Mitternacht am Montag der Woche, in der `date` liegt.
    public func weekStartDate(containing date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date)) ?? date
    }

    /// Die sieben Tage ab dem Montag; leer bei einem ungültigen Datum.
    public func dates(inWeekStarting weekStart: String) -> [String] {
        (0..<7).compactMap { addingDays($0, to: weekStart) }
    }

    /// `count` Tage ab `key` (einschließlich), unabhängig vom Wochentag.
    public func dates(from key: String, count: Int = 7) -> [String] {
        (0..<max(count, 0)).compactMap { addingDays($0, to: key) }
    }

    public func addingDays(_ days: Int, to key: String) -> String? {
        guard let start = date(from: key), let shifted = calendar.date(byAdding: .day, value: days, to: start) else { return nil }
        return self.key(for: shifted)
    }

    public func weekdayShort(_ key: String) -> String {
        guard let date = date(from: key) else { return key }
        return Self.shortNames[calendar.component(.weekday, from: date) - 1]
    }

    public func weekdayName(_ key: String) -> String {
        guard let date = date(from: key) else { return key }
        return Self.longNames[calendar.component(.weekday, from: date) - 1]
    }
}
