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

    /// 3,8 km in unter 60 Minuten bis zum 04.07.2027.
    public static let `default`: AthleteGoal = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let date = calendar.date(from: DateComponents(year: 2027, month: 7, day: 4)) ?? Date.distantFuture
        return AthleteGoal(distanceMeters: 3800, targetDurationSeconds: 3600, targetDate: date)
    }()
}
