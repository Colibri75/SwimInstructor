import Foundation

/// Ergebnis eines Health-Durchlaufs: der Snapshot fürs Backend und die Workouts, aus denen er
/// entstanden ist (die App zeigt sie als "bisherige Einheiten").
public struct AthleteStateReading: Equatable, Sendable {
    public let snapshot: AthleteStateSnapshot
    /// Bereinigt um Duplikate, neueste zuerst.
    public let workouts: [SwimWorkout]
    /// `false`, wenn die Erholungswerte nicht gelesen werden konnten; der Snapshot hat dann
    /// Erholungsstatus `unknown`.
    public let vitalsAvailable: Bool

    public init(snapshot: AthleteStateSnapshot, workouts: [SwimWorkout], vitalsAvailable: Bool) {
        self.snapshot = snapshot
        self.workouts = workouts
        self.vitalsAvailable = vitalsAvailable
    }
}

public protocol SnapshotBuilding {
    func build(now: Date) async throws -> AthleteStateReading
}

/// Liest Workouts und Tageswerte aus Health und rechnet daraus den Snapshot (M3-Berechnung).
///
/// Die Zeitfenster richten sich nach dem, was `AthleteStateCalculator` auswertet: Workouts der
/// letzten 56 Tage (Pace-Vergleich Woche 1 bis 4 gegen 5 bis 8), Tageswerte der letzten 31 Tage
/// (aktuell Tag 0 bis 2, Baseline Tag 3 bis 30).
public struct SnapshotBuilder: SnapshotBuilding {
    public static let workoutWindowDays = 56
    public static let vitalsWindowDays = 31

    private let workoutRepository: SwimWorkoutRepository
    private let vitalsRepository: DailyVitalsRepository
    private let calculator: AthleteStateCalculator
    /// Wird bei jedem Durchlauf gelesen: Ein in den Einstellungen geändertes Ziel gilt sofort.
    private let goalProvider: () -> AthleteGoal
    private let calendar: Calendar

    public init(
        workoutRepository: SwimWorkoutRepository,
        vitalsRepository: DailyVitalsRepository,
        goal: AthleteGoal = .default,
        calendar: Calendar = .current
    ) {
        self.workoutRepository = workoutRepository
        self.vitalsRepository = vitalsRepository
        self.calculator = AthleteStateCalculator(calendar: calendar)
        self.goalProvider = { goal }
        self.calendar = calendar
    }

    /// Wie oben, mit einem Ziel, das bei jedem Durchlauf neu gelesen wird (etwa aus den Einstellungen).
    public init(
        workoutRepository: SwimWorkoutRepository,
        vitalsRepository: DailyVitalsRepository,
        goalProvider: @escaping () -> AthleteGoal,
        calendar: Calendar = .current
    ) {
        self.workoutRepository = workoutRepository
        self.vitalsRepository = vitalsRepository
        self.calculator = AthleteStateCalculator(calendar: calendar)
        self.goalProvider = goalProvider
        self.calendar = calendar
    }

    public func build(now: Date = Date()) async throws -> AthleteStateReading {
        let today = calendar.startOfDay(for: now)
        let workoutStart = calendar.date(byAdding: .day, value: -(Self.workoutWindowDays - 1), to: today) ?? today
        let vitalsStart = calendar.date(byAdding: .day, value: -(Self.vitalsWindowDays - 1), to: today) ?? today

        let workouts = try await workoutRepository.fetchSwimWorkouts(from: workoutStart)

        // Ohne Erholungswerte gibt es trotzdem einen Plan (Status unknown); ohne Workouts nicht,
        // denn dann wäre der Snapshot falsch statt nur unvollständig.
        var vitals: [DailyVitals] = []
        var vitalsAvailable = true
        do {
            vitals = try await vitalsRepository.fetchDailyVitals(from: vitalsStart)
        } catch {
            vitalsAvailable = false
        }

        let snapshot = calculator.snapshot(workouts: workouts, vitals: vitals, goal: goalProvider(), now: now)
        let cleaned = SwimWorkoutDeduplicator.deduplicate(workouts)
            .filter { $0.startDate <= now }
            .sorted { $0.startDate > $1.startDate }
        return AthleteStateReading(snapshot: snapshot, workouts: cleaned, vitalsAvailable: vitalsAvailable)
    }
}
