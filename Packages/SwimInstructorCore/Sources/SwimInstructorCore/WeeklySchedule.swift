import Foundation

/// Der Wochenraster (P2): je Wochentag, ob, wann und wie lange der Athlet trainiert, auf Wunsch mit fester Sportart.
/// Er ersetzt Trainingstage und Wochenstunden im Ziel (`applied(to:)` rechnet sie daraus) und geht als
/// `training_goal.weekly_schedule` zum Server. Er gehört nicht zum Ziel: Eine Änderung wirkt ab der nächsten
/// Abstimmung der Woche und ändert den Gesamtplan nicht.
public struct WeeklySchedule: Codable, Equatable, Sendable {
    public enum TimeOfDay: String, Codable, Sendable, CaseIterable, Identifiable {
        case morning
        case midday
        case evening

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .morning: return String(localized: "Morgens")
            case .midday: return String(localized: "Mittags")
            case .evening: return String(localized: "Abends")
            }
        }
    }

    public struct Day: Codable, Equatable, Sendable, Identifiable {
        /// 1 = Montag bis 7 = Sonntag.
        public var weekday: Int
        public var trains: Bool
        public var timeOfDay: TimeOfDay?
        /// Höchstens so viele Minuten an diesem Tag (0 an Ruhetagen).
        public var maxMinutes: Int
        /// Nur diese Sportart an diesem Tag; `nil`: die App verteilt.
        public var sport: SportID?

        public var id: Int { weekday }

        public init(weekday: Int, trains: Bool, timeOfDay: TimeOfDay? = nil, maxMinutes: Int, sport: SportID? = nil) {
            self.weekday = weekday
            self.trains = trains
            self.timeOfDay = timeOfDay
            self.maxMinutes = maxMinutes
            self.sport = sport
        }

        public var name: String { WeeklySchedule.weekdayNames[weekday - 1] }
    }

    /// Montag zuerst, in der Sprache der App.
    public static var weekdayNames: [String] {
        let names = WeekCalendar.longNames
        return Array(names.dropFirst()) + names.prefix(1)
    }
    /// Minuten an einem Trainingstag; Gegenstück: `ScheduleDaySchema` im Server (15 bis 600).
    public static let minutesRange = 15...600
    public static let minutesStep = 15

    /// Genau sieben Tage, Montag zuerst.
    public var days: [Day]

    public init(days: [Day]) {
        self.days = days
    }

    /// Ein Wochenraster aus Trainingstagen und Wochenstunden (Ziele von vor P2): die Tage nach einem festen Muster
    /// (Dienstag, Donnerstag und Samstag zuerst), die Zeit gleich verteilt.
    public init(trainingDaysPerWeek: Int, weeklyHours: Double) {
        let count = min(max(trainingDaysPerWeek, 1), 7)
        let patterns: [[Int]] = [[6], [2, 6], [2, 4, 6], [2, 4, 6, 7], [2, 3, 4, 6, 7], [2, 3, 4, 5, 6, 7], [1, 2, 3, 4, 5, 6, 7]]
        let training = Set(patterns[count - 1])
        let perDay = Self.clampMinutes(Int((weeklyHours * 60 / Double(count)).rounded()))
        days = (1...7).map { weekday in
            Day(weekday: weekday, trains: training.contains(weekday), maxMinutes: training.contains(weekday) ? perDay : 0)
        }
    }

    /// Auf das Raster von 15 Minuten und den erlaubten Bereich gebracht.
    public static func clampMinutes(_ minutes: Int) -> Int {
        let stepped = Int((Double(minutes) / Double(minutesStep)).rounded()) * minutesStep
        return min(max(stepped, minutesRange.lowerBound), minutesRange.upperBound)
    }

    public var trainingDays: Int { days.filter(\.trains).count }

    public var totalMinutes: Int { days.filter(\.trains).reduce(0) { $0 + $1.maxMinutes } }

    public func day(_ weekday: Int) -> Day? {
        days.first { $0.weekday == weekday }
    }

    /// Der Tag des Rasters für das Datum `key` (`yyyy-MM-dd`).
    public func day(on key: String, weekCalendar: WeekCalendar = WeekCalendar()) -> Day? {
        weekCalendar.weekdayNumber(key).flatMap { day($0) }
    }

    /// Ersetzt einen Tag; an einem Ruhetag gibt es keine Minuten, keine Tageszeit und keine Sportart.
    public func setting(_ day: Day) -> WeeklySchedule {
        var copy = self
        guard let index = copy.days.firstIndex(where: { $0.weekday == day.weekday }) else { return self }
        var cleaned = day
        if cleaned.trains {
            cleaned.maxMinutes = Self.clampMinutes(cleaned.maxMinutes)
        } else {
            cleaned = Day(weekday: day.weekday, trains: false, maxMinutes: 0)
        }
        copy.days[index] = cleaned
        return copy
    }

    /// Was nicht passt, auf Deutsch; `nil`, wenn der Wochenraster gültig ist.
    public func problem(registry: SportRegistry = .standard) -> String? {
        guard days.map(\.weekday) == Array(1...7) else { return String(localized: "Der Wochenraster braucht jeden Wochentag genau einmal.") }
        guard trainingDays > 0 else { return String(localized: "Mindestens ein Tag mit Training.") }
        for day in days where day.trains {
            let name = day.name
            guard Self.minutesRange.contains(day.maxMinutes) else { return String(localized: "\(name): 15 bis 600 Minuten.") }
            if let sport = day.sport, registry.module(for: sport) == nil { return String(localized: "\(name): unbekannte Sportart.") }
        }
        return nil
    }

    /// Das Ziel mit Trainingstagen und Wochenstunden aus diesem Wochenraster (für Server ohne Wochenraster und für den
    /// Gesamtplan), Stunden auf eine Viertelstunde gerundet und im Bereich des Ziels.
    public func applied(to goal: TrainingGoal) -> TrainingGoal {
        var copy = goal
        copy.trainingDaysPerWeek = min(max(trainingDays, TrainingGoal.trainingDaysRange.lowerBound), TrainingGoal.trainingDaysRange.upperBound)
        let hours = (Double(totalMinutes) / 60 * 4).rounded() / 4
        copy.weeklyHours = min(max(hours, TrainingGoal.weeklyHoursRange.lowerBound), TrainingGoal.weeklyHoursRange.upperBound)
        return copy
    }

    /// Kurzfassung für die Einstellungen, z. B. "4 Tage, 5 h 15 min".
    public var summary: String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let time = minutes == 0 ? "\(hours) h" : hours == 0 ? "\(minutes) min" : "\(hours) h \(minutes) min"
        return trainingDays == 1 ? String(localized: "1 Tag, \(time)") : String(localized: "\(trainingDays) Tage, \(time)")
    }
}

/// Speichert den Wochenraster auf dem Gerät.
public protocol WeeklyScheduleStoring {
    /// Der gespeicherte Wochenraster, `nil`, wenn noch keiner eingestellt ist.
    func storedSchedule() -> WeeklySchedule?
    /// Speichert einen gültigen Wochenraster; sonst bleibt der alte und es kommt `false`.
    @discardableResult func setSchedule(_ schedule: WeeklySchedule) -> Bool
}

public extension WeeklyScheduleStoring {
    /// Der gespeicherte Wochenraster oder, ohne ihn, einer aus Trainingstagen und Stunden des Ziels.
    func schedule(for goal: TrainingGoal) -> WeeklySchedule {
        storedSchedule() ?? WeeklySchedule(trainingDaysPerWeek: goal.trainingDaysPerWeek, weeklyHours: goal.weeklyHours)
    }
}

public struct UserDefaultsWeeklyScheduleStore: WeeklyScheduleStoring {
    static let storageKey = "settings.weeklySchedule"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func storedSchedule() -> WeeklySchedule? {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(WeeklySchedule.self, from: data),
              stored.problem() == nil else { return nil }
        return stored
    }

    @discardableResult
    public func setSchedule(_ schedule: WeeklySchedule) -> Bool {
        guard schedule.problem() == nil, let data = try? JSONEncoder().encode(schedule) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }
}
