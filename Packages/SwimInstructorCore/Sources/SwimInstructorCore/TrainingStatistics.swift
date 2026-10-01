import Foundation

/// Eine Kalenderwoche des Dashboards.
public struct WeeklyVolume: Identifiable, Equatable, Sendable {
    /// Erster Tag der Woche (Mitternacht, nach dem verwendeten Kalender).
    public let weekStart: Date
    public let meters: Double
    public let sessions: Int
    /// Gewichtete Pace der Woche (Gesamtzeit durch Gesamtstrecke), `nil` ohne Strecke.
    public let averagePaceSecondsPer100m: Double?
    /// Die laufende Woche ist noch nicht vorbei und deshalb meist kleiner.
    public let isCurrentWeek: Bool

    public var id: Date { weekStart }

    public init(weekStart: Date, meters: Double, sessions: Int, averagePaceSecondsPer100m: Double?, isCurrentWeek: Bool) {
        self.weekStart = weekStart
        self.meters = meters
        self.sessions = sessions
        self.averagePaceSecondsPer100m = averagePaceSecondsPer100m
        self.isCurrentWeek = isCurrentWeek
    }
}

/// Eine Einheit als Punkt im Pace-Diagramm.
public struct PaceSample: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let paceSecondsPer100m: Double
    public let distanceMeters: Double

    public init(id: UUID, date: Date, paceSecondsPer100m: Double, distanceMeters: Double) {
        self.id = id
        self.date = date
        self.paceSecondsPer100m = paceSecondsPer100m
        self.distanceMeters = distanceMeters
    }
}

/// Rechnet Workouts in die Zahlen des Dashboards um. Rein rechnerisch, ohne HealthKit und UI.
public struct TrainingStatistics: Sendable {
    /// Einheiten unter dieser Strecke sagen nichts über das Tempo aus (kurze Technikeinheiten,
    /// abgebrochene Workouts) und bleiben aus dem Pace-Diagramm heraus.
    public static let minimumDistanceForPace: Double = 200

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Die letzten `weeks` Kalenderwochen bis einschließlich der laufenden, älteste zuerst.
    /// Wochen ohne Einheit stehen mit 0 m drin, damit das Diagramm Lücken zeigt.
    public func weeklyVolumes(workouts: [SwimWorkout], weeks: Int = 8, now: Date) -> [WeeklyVolume] {
        guard weeks > 0, let currentStart = weekStart(of: now) else { return [] }

        var result: [WeeklyVolume] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }

            let inWeek = workouts.filter { $0.startDate >= start && $0.startDate < end }
            let withDistance = inWeek.filter { ($0.totalDistanceMeters ?? 0) > 0 }
            let meters = withDistance.reduce(0.0) { $0 + ($1.totalDistanceMeters ?? 0) }
            let seconds = withDistance.reduce(0.0) { $0 + $1.duration }

            result.append(WeeklyVolume(
                weekStart: start,
                meters: meters,
                sessions: inWeek.count,
                averagePaceSecondsPer100m: meters > 0 ? seconds / (meters / 100) : nil,
                isCurrentWeek: offset == 0
            ))
        }
        return result
    }

    /// Pace je Einheit der letzten `days` Tage, älteste zuerst.
    public func paceSamples(workouts: [SwimWorkout], days: Int = 56, now: Date) -> [PaceSample] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        return workouts
            .filter { $0.startDate >= start && $0.startDate <= now }
            .compactMap { workout -> PaceSample? in
                guard let distance = workout.totalDistanceMeters,
                      distance >= Self.minimumDistanceForPace,
                      let pace = workout.averagePaceSecondsPer100m else { return nil }
                return PaceSample(id: workout.id, date: workout.startDate, paceSecondsPer100m: pace, distanceMeters: distance)
            }
            .sorted { $0.date < $1.date }
    }

    private func weekStart(of date: Date) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }
}
