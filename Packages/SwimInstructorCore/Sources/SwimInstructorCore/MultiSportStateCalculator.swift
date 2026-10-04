import Foundation

/// Rechnet die v2-Teile des Snapshots: Werte je Sportart und Gesamtlast aus den Einheiten aller Sportarten, dazu das
/// Gesamtziel in der Form für den Server. Fenster wie `AthleteStateCalculator`: letzte 7 Tage sind Tag 0 bis 6,
/// der Wochenschnitt ist die Summe von Tag 0 bis 27 geteilt durch 4.
public struct MultiSportStateCalculator: Sendable {
    public let registry: SportRegistry
    public let calendar: Calendar
    public let loadCalculator: TrainingLoadCalculator

    public init(registry: SportRegistry = .standard, calendar: Calendar = .current, loadCalculator: TrainingLoadCalculator? = nil) {
        self.registry = registry
        self.calendar = calendar
        self.loadCalculator = loadCalculator ?? TrainingLoadCalculator(registry: registry)
    }

    /// Der v1-Snapshot erweitert um Gesamtziel, Werte je Sportart und Gesamtlast (Schema v2). Mit `schedule` gehen der
    /// Wochenraster mit und Trainingstage und Stunden aus ihm (`WeeklySchedule.applied(to:)`).
    public func extend(
        _ snapshot: AthleteStateSnapshot,
        workouts: [Workout],
        goal: TrainingGoal,
        schedule: WeeklySchedule? = nil,
        now: Date
    ) -> AthleteStateSnapshot {
        let goal = schedule.map { $0.applied(to: goal) } ?? goal
        let dated = WorkoutDeduplicator.deduplicate(workouts)
            .filter { $0.startDate <= now && registry.module(for: $0.sport) != nil }
            .map { Dated(workout: $0, day: dayDistance(from: $0.startDate, to: now)) }
            .filter { (0...27).contains($0.day) }

        // Jede Sportart mit Training in den letzten 4 Wochen, im Ziel oder mit Schwerpunkt; Reihenfolge der Registry.
        let relevant = Set(dated.map { $0.workout.sport })
            .union(goal.disciplines.map(\.sport))
            .union(goal.emphasis.filter { $0.percent > 0 }.map(\.sport))
        let sports = registry.ids.filter { relevant.contains($0) }.map { sport in
            summary(sport: sport, sessions: dated.filter { $0.workout.sport == sport })
        }

        return snapshot.withMultiSport(
            trainingGoal: AthleteStateSnapshot.TrainingGoalSummary(
                template: goal.template,
                kind: goal.kind,
                targetDate: goal.targetDate,
                daysUntilGoal: max(0, dayDistance(from: now, to: goal.targetDate)),
                trainingDaysPerWeek: goal.trainingDaysPerWeek,
                weeklyHours: goal.weeklyHours,
                disciplines: goal.disciplines,
                emphasis: goal.emphasis,
                weeklySchedule: schedule?.days
            ),
            sports: sports,
            totalLoad: totalLoad(sessions: dated)
        )
    }

    private func summary(sport: SportID, sessions: [Dated]) -> AthleteStateSnapshot.SportStateSummary {
        let lastSeven = sessions.filter { $0.day <= 6 }.map { $0.workout }
        let fourWeeks = sessions.map { $0.workout }
        return AthleteStateSnapshot.SportStateSummary(
            sport: sport,
            sessionsLastSevenDays: lastSeven.count,
            sessionsLastFourWeeks: fourWeeks.count,
            minutesLastSevenDays: (minutes(lastSeven)).rounded(),
            averageWeeklyMinutes: (minutes(fourWeeks) / 4).rounded(),
            metersLastSevenDays: meters(lastSeven).rounded(),
            averageWeeklyMeters: (meters(fourWeeks) / 4).rounded(),
            longestSessionMeters: (fourWeeks.compactMap(\.distanceMeters).max() ?? 0).rounded(),
            longestSessionMinutes: ((fourWeeks.map(\.duration).max() ?? 0) / 60).rounded(),
            loadLastSevenDays: tenths(load(lastSeven)),
            averageWeeklyLoad: tenths(load(fourWeeks) / 4),
            daysSinceLastSession: sessions.map { $0.day }.min()
        )
    }

    private func totalLoad(sessions: [Dated]) -> AthleteStateSnapshot.TotalLoadSummary {
        let lastSeven = sessions.filter { $0.day <= 6 }.map { $0.workout }
        let fourWeeks = sessions.map { $0.workout }
        let acute = load(lastSeven)
        let chronic = load(fourWeeks) / 4
        return AthleteStateSnapshot.TotalLoadSummary(
            minutesLastSevenDays: minutes(lastSeven).rounded(),
            averageWeeklyMinutes: (minutes(fourWeeks) / 4).rounded(),
            loadLastSevenDays: tenths(acute),
            averageWeeklyLoad: tenths(chronic),
            acuteChronicRatio: chronic > 0 ? (acute / chronic * 100).rounded() / 100 : nil
        )
    }

    private struct Dated {
        let workout: Workout
        /// Kalendertage vor heute (0 = heute).
        let day: Int
    }

    private func minutes(_ workouts: [Workout]) -> Double {
        workouts.reduce(0) { $0 + max(0, $1.duration) } / 60
    }

    private func meters(_ workouts: [Workout]) -> Double {
        workouts.reduce(0) { $0 + ($1.distanceMeters ?? 0) }
    }

    private func load(_ workouts: [Workout]) -> Double {
        workouts.reduce(0) { $0 + loadCalculator.load(of: $1) }
    }

    private func tenths(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private func dayDistance(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}
