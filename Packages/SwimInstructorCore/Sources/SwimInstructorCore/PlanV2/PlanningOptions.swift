import Foundation

// MARK: - Kraft und Mobilität

/// Wie oft pro Woche Kraft und Mobilität dazukommen (Einstellungen). Geht als `supplements` mit Tages- und Wochenplan.
public struct Supplements: Codable, Equatable, Sendable {
    public static let strengthRange: ClosedRange<Int> = 0...3
    public static let mobilityRange: ClosedRange<Int> = 0...7
    public static let none = Supplements(strengthPerWeek: 0, mobilityPerWeek: 0)

    public var strengthPerWeek: Int
    public var mobilityPerWeek: Int

    public init(strengthPerWeek: Int, mobilityPerWeek: Int) {
        self.strengthPerWeek = min(max(strengthPerWeek, Self.strengthRange.lowerBound), Self.strengthRange.upperBound)
        self.mobilityPerWeek = min(max(mobilityPerWeek, Self.mobilityRange.lowerBound), Self.mobilityRange.upperBound)
    }

    public var isEmpty: Bool { strengthPerWeek == 0 && mobilityPerWeek == 0 }

    public func perWeek(_ kind: ExtraKind) -> Int {
        switch kind {
        case .strength: return strengthPerWeek
        case .mobility: return mobilityPerWeek
        case .unknown: return 0
        }
    }
}

// MARK: - Ort und Kalender

/// Ein ungefährer Ort für die Wettervorhersage, auf eine Nachkommastelle gerundet (etwa 10 km). Genauer verlässt der Ort
/// das Gerät nie.
public struct GeoPoint: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = (min(max(latitude, -90), 90) * 10).rounded() / 10
        self.longitude = (min(max(longitude, -180), 180) * 10).rounded() / 10
    }
}

/// Freie Zeit an einem Tag laut Kalender (längster freier Block im Trainingsfenster), in Minuten.
public struct DayAvailability: Codable, Equatable, Sendable {
    public let date: String
    public let minutes: Int

    public init(date: String, minutes: Int) {
        self.date = date
        self.minutes = max(minutes, 0)
    }
}

public enum CalendarAvailability {
    /// Der längste freie Block an `day` zwischen `startHour` und `endHour`, ohne die belegten Zeiten `busy`. Ein
    /// Termin, der über das Fenster hinausragt, zählt nur innerhalb des Fensters.
    public static func freeMinutes(busy: [DateInterval], day: Date, startHour: Int, endHour: Int, calendar: Calendar = .current) -> Int {
        let midnight = calendar.startOfDay(for: day)
        guard endHour > startHour,
              let windowStart = calendar.date(byAdding: .hour, value: startHour, to: midnight),
              let windowEnd = calendar.date(byAdding: .hour, value: endHour, to: midnight) else { return 0 }
        let blocks = busy
            .compactMap { interval -> DateInterval? in
                let start = max(interval.start, windowStart)
                let end = min(interval.end, windowEnd)
                return start < end ? DateInterval(start: start, end: end) : nil
            }
            .sorted { $0.start < $1.start }
        var longest: TimeInterval = 0
        var cursor = windowStart
        for block in blocks {
            if block.start > cursor { longest = max(longest, block.start.timeIntervalSince(cursor)) }
            cursor = max(cursor, block.end)
        }
        longest = max(longest, windowEnd.timeIntervalSince(cursor))
        return Int((longest / 60).rounded(.down))
    }
}

// MARK: - Einstellungen

/// Was der Plan außer dem Training berücksichtigt: Kraft und Mobilität, Wetter am Ort, freie Zeit laut Kalender.
public struct PlanningPreferences: Codable, Equatable, Sendable {
    public static let hourRange: ClosedRange<Int> = 0...24
    public static let standard = PlanningPreferences(supplements: .none, usesWeather: false, usesCalendar: false, calendarStartHour: 6, calendarEndHour: 21)

    public var supplements: Supplements
    public var usesWeather: Bool
    public var usesCalendar: Bool
    /// Das Trainingsfenster des Tages für den Kalender.
    public var calendarStartHour: Int
    public var calendarEndHour: Int

    public init(supplements: Supplements, usesWeather: Bool, usesCalendar: Bool, calendarStartHour: Int, calendarEndHour: Int) {
        self.supplements = supplements
        self.usesWeather = usesWeather
        self.usesCalendar = usesCalendar
        let start = min(max(calendarStartHour, Self.hourRange.lowerBound), Self.hourRange.upperBound - 1)
        self.calendarStartHour = start
        self.calendarEndHour = min(max(calendarEndHour, start + 1), Self.hourRange.upperBound)
    }
}

public protocol PlanningPreferencesStoring {
    func preferences() -> PlanningPreferences
    func save(_ preferences: PlanningPreferences)
}

public struct UserDefaultsPlanningPreferencesStore: PlanningPreferencesStoring {
    static let storageKey = "settings.planningPreferences"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func preferences() -> PlanningPreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(PlanningPreferences.self, from: data) else { return .standard }
        // Über die Initialisierer, damit gespeicherte Werte außerhalb der Bereiche eingefangen werden.
        return PlanningPreferences(
            supplements: Supplements(strengthPerWeek: stored.supplements.strengthPerWeek, mobilityPerWeek: stored.supplements.mobilityPerWeek),
            usesWeather: stored.usesWeather,
            usesCalendar: stored.usesCalendar,
            calendarStartHour: stored.calendarStartHour,
            calendarEndHour: stored.calendarEndHour
        )
    }

    public func save(_ preferences: PlanningPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Was die App außer Zustand und Training mit einer Planung schickt (aus Einstellungen, Ort und Kalender).
public struct PlanningExtras: Equatable, Sendable {
    public var supplements: Supplements?
    public var location: GeoPoint?
    /// Freie Zeit je Tag laut Kalender (nur die angefragten Tage).
    public var availability: [DayAvailability]

    public init(supplements: Supplements? = nil, location: GeoPoint? = nil, availability: [DayAvailability] = []) {
        self.supplements = supplements
        self.location = location
        self.availability = availability
    }

    public static let none = PlanningExtras()

    /// Die freie Zeit an `date`, `nil` ohne Angabe.
    public func availableMinutes(on date: String) -> Int? {
        availability.first { $0.date == date }?.minutes
    }
}
