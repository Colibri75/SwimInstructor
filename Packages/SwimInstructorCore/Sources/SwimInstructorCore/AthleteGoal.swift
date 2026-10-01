import Foundation

/// Das Trainingsziel, auf das der Plan hinarbeitet.
public struct AthleteGoal: Codable, Equatable, Sendable {
    public let distanceMeters: Double
    public let targetDurationSeconds: TimeInterval
    public let targetDate: Date

    public init(distanceMeters: Double, targetDurationSeconds: TimeInterval, targetDate: Date) {
        self.distanceMeters = distanceMeters
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDate = targetDate
    }

    /// Zielpace in Sekunden pro 100 m (3800 m in 3600 s ergibt ca. 94,7).
    public var targetPaceSecondsPerHundredMeters: Double {
        targetDurationSeconds / (distanceMeters / 100)
    }

    // MARK: - Eingabe in den Einstellungen

    /// Die Grenzen, in denen ein Ziel gilt (der Server nimmt Zielpace zwischen 20 und 1200 s pro 100 m,
    /// die App ist enger, damit kein Tippfehler einen unsinnigen Plan auslöst).
    public static let distanceRange: ClosedRange<Double> = 100...10_000
    public static let durationMinutesRange: ClosedRange<Int> = 1...600
    public static let paceRange: ClosedRange<Double> = 40...600

    /// Was an dem Ziel nicht passt, auf Deutsch; `nil`, wenn es gültig ist.
    public var problem: String? {
        guard Self.distanceRange.contains(distanceMeters) else {
            return "Die Distanz muss zwischen 100 m und 10 km liegen."
        }
        guard targetDurationSeconds >= 60, targetDurationSeconds <= Double(Self.durationMinutesRange.upperBound * 60) else {
            return "Die Zielzeit muss zwischen 1 und 600 Minuten liegen."
        }
        guard Self.paceRange.contains(targetPaceSecondsPerHundredMeters) else {
            return "Distanz und Zeit ergeben eine Zielpace außerhalb von 0:40 bis 10:00 pro 100 m."
        }
        return nil
    }

    /// Der Zieltag als Mittag (Berlin), so wie beim Standardziel: Ein Zieltag ist ein Kalendertag.
    /// `day` ist ein beliebiger Zeitpunkt an diesem Tag, gelesen im Kalender des Geräts.
    public static func targetDate(onDayOf day: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let components = DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12)
        return berlin.date(from: components) ?? day
    }

    /// 3,8 km in unter 60 Minuten bis zum 04.07.2027.
    ///
    /// Das Datum liegt bewusst auf Mittag (Berlin): Ein Zieltag ist ein Kalendertag, keine
    /// Uhrzeit. Mittag bleibt in jeder Zeitzone von UTC-10 bis UTC+13 derselbe Kalendertag,
    /// Mitternacht dagegen würde je nach Gerät um einen Tag verrutschen.
    public static let `default`: AthleteGoal = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let components = DateComponents(year: 2027, month: 7, day: 4, hour: 12)
        let date = calendar.date(from: components) ?? Date.distantFuture
        return AthleteGoal(distanceMeters: 3800, targetDurationSeconds: 3600, targetDate: date)
    }()
}
