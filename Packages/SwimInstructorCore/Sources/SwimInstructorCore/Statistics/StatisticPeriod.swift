import Foundation

/// Ein Zeitraum aus ganzen Tagen, Ende ausgeschlossen.
public struct StatisticInterval: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// Über welchen Zeitraum eine Kachel rechnet. Alle Zeiträume enden mit heute; der Vergleich läuft über dieselben Tage
/// davor (bei "Diese Woche": Vorwoche von Montag bis zum selben Wochentag).
///
/// Die App liest Einheiten und Tageswerte der letzten 56 Tage (`SnapshotBuilder`): genug für 8 Wochen, oder 4 Wochen
/// samt Vergleich.
public enum StatisticPeriod: String, Codable, CaseIterable, Sendable {
    case currentWeek = "week"
    case sevenDays = "7_days"
    case fourWeeks = "4_weeks"
    case eightWeeks = "8_weeks"

    /// Gilt, wenn eine gespeicherte Kachel einen Zeitraum nennt, den diese App-Version nicht kennt.
    public static let standard = StatisticPeriod.fourWeeks

    public var displayName: String {
        switch self {
        case .currentWeek: return String(localized: "Diese Woche")
        case .sevenDays: return String(localized: "7 Tage")
        case .fourWeeks: return String(localized: "4 Wochen")
        case .eightWeeks: return String(localized: "8 Wochen")
        }
    }

    /// Name des Vergleichszeitraums; `nil` ohne Vergleich (für 8 Wochen davor fehlen die Daten).
    public var comparisonName: String? {
        switch self {
        case .currentWeek: return String(localized: "Vorwoche")
        case .sevenDays: return String(localized: "7 Tage davor")
        case .fourWeeks: return String(localized: "4 Wochen davor")
        case .eightWeeks: return nil
        }
    }

    /// Um so viele Tage liegt der Vergleich zurück.
    var lengthInDays: Int {
        switch self {
        case .currentWeek, .sevenDays: return 7
        case .fourWeeks: return 28
        case .eightWeeks: return 56
        }
    }

    /// Ein Balken oder Punkt im Verlauf steht für so viele Tage.
    var bucketDays: Int {
        switch self {
        case .currentWeek, .sevenDays: return 1
        case .fourWeeks, .eightWeeks: return 7
        }
    }

    /// Von Mitternacht des ersten Tags bis Mitternacht nach heute.
    public func interval(now: Date, calendar: Calendar = .current) -> StatisticInterval {
        let today = calendar.startOfDay(for: now)
        let end = Self.adding(1, to: today, calendar)
        switch self {
        case .currentWeek:
            return StatisticInterval(start: WeekCalendar(calendar: calendar).weekStartDate(containing: now), end: end)
        default:
            return StatisticInterval(start: Self.adding(-(lengthInDays - 1), to: today, calendar), end: end)
        }
    }

    /// Dieselben Tage davor; `nil` ohne Vergleich.
    public func previousInterval(now: Date, calendar: Calendar = .current) -> StatisticInterval? {
        guard comparisonName != nil else { return nil }
        let current = interval(now: now, calendar: calendar)
        return StatisticInterval(
            start: Self.adding(-lengthInDays, to: current.start, calendar),
            end: Self.adding(-lengthInDays, to: current.end, calendar)
        )
    }

    /// Die Abschnitte des Verlaufs, ältester zuerst: Tage (Diese Woche: Montag bis Sonntag, auch die kommenden) oder
    /// Wochen ab dem ersten Tag.
    public func buckets(now: Date, calendar: Calendar = .current) -> [StatisticInterval] {
        let start = interval(now: now, calendar: calendar).start
        return (0..<(lengthInDays / bucketDays)).map { index in
            StatisticInterval(
                start: Self.adding(index * bucketDays, to: start, calendar),
                end: Self.adding((index + 1) * bucketDays, to: start, calendar)
            )
        }
    }

    private static func adding(_ days: Int, to date: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days) * 86_400)
    }
}
