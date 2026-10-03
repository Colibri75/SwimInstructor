import Foundation

/// Ergebnis eines Health-Durchlaufs: der Snapshot fürs Backend und die Workouts, aus denen er
/// entstanden ist (die App zeigt sie als "bisherige Einheiten").
public struct AthleteStateReading: Equatable, Sendable {
    public let snapshot: AthleteStateSnapshot
    /// Die Schwimmeinheiten, bereinigt um Duplikate, neueste zuerst (Grundlage von Snapshot v1 und Statistik).
    public let workouts: [SwimWorkout]
    /// Die Einheiten aller Sportarten, bereinigt um Duplikate je Sportart, neueste zuerst.
    public let allWorkouts: [Workout]
    /// `false`, wenn die Erholungswerte nicht gelesen werden konnten; der Snapshot hat dann
    /// Erholungsstatus `unknown`.
    public let vitalsAvailable: Bool

    public init(
        snapshot: AthleteStateSnapshot,
        workouts: [SwimWorkout],
        allWorkouts: [Workout]? = nil,
        vitalsAvailable: Bool
    ) {
        self.snapshot = snapshot
        self.workouts = workouts
        // Ohne eigene Angabe (ältere Aufrufer, Tests): die Schwimmeinheiten.
        self.allWorkouts = allWorkouts ?? workouts.map(Workout.init(swim:))
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

    /// Alle Einheiten ab einem Datum, aus welchem Repository auch immer.
    private let fetchWorkouts: (Date) async throws -> [Workout]
    private let vitalsRepository: DailyVitalsRepository
    private let calculator: AthleteStateCalculator
    /// Wird bei jedem Durchlauf gelesen: Ein in den Einstellungen geändertes Ziel gilt sofort.
    private let goalProvider: () -> AthleteGoal
    /// Gesetzt: Der Snapshot geht als v2 mit Gesamtziel und allen Sportarten zum Server.
    private let trainingGoalProvider: (() -> TrainingGoal)?
    private let calendar: Calendar

    public init(
        workoutRepository: SwimWorkoutRepository,
        vitalsRepository: DailyVitalsRepository,
        goal: AthleteGoal = .default,
        calendar: Calendar = .current
    ) {
        self.fetchWorkouts = { try await workoutRepository.fetchSwimWorkouts(from: $0).map(Workout.init(swim:)) }
        self.vitalsRepository = vitalsRepository
        self.calculator = AthleteStateCalculator(calendar: calendar)
        self.goalProvider = { goal }
        self.trainingGoalProvider = nil
        self.calendar = calendar
    }

    /// Wie oben, mit einem Ziel, das bei jedem Durchlauf neu gelesen wird (etwa aus den Einstellungen).
    public init(
        workoutRepository: SwimWorkoutRepository,
        vitalsRepository: DailyVitalsRepository,
        goalProvider: @escaping () -> AthleteGoal,
        calendar: Calendar = .current
    ) {
        self.fetchWorkouts = { try await workoutRepository.fetchSwimWorkouts(from: $0).map(Workout.init(swim:)) }
        self.vitalsRepository = vitalsRepository
        self.calculator = AthleteStateCalculator(calendar: calendar)
        self.goalProvider = goalProvider
        self.trainingGoalProvider = nil
        self.calendar = calendar
    }

    /// Liest die Einheiten aller Sportarten. Snapshot v1 und Statistik sehen davon weiter nur das Schwimmen.
    public init(
        repository: WorkoutRepository,
        vitalsRepository: DailyVitalsRepository,
        goalProvider: @escaping () -> AthleteGoal,
        calendar: Calendar = .current
    ) {
        self.fetchWorkouts = { try await repository.fetchWorkouts(from: $0) }
        self.vitalsRepository = vitalsRepository
        self.calculator = AthleteStateCalculator(calendar: calendar)
        self.goalProvider = goalProvider
        self.trainingGoalProvider = nil
        self.calendar = calendar
    }

    /// Snapshot v2: liest die Einheiten aller Sportarten und das Gesamtziel (bei jedem Durchlauf neu). Die v1-Felder
    /// rechnen mit dem Schwimmteil des Ziels (`legacySwimGoal`) genau wie bisher.
    public init(
        repository: WorkoutRepository,
        vitalsRepository: DailyVitalsRepository,
        trainingGoalProvider: @escaping () -> TrainingGoal,
        calendar: Calendar = .current
    ) {
        self.fetchWorkouts = { try await repository.fetchWorkouts(from: $0) }
        self.vitalsRepository = vitalsRepository
        self.calculator = AthleteStateCalculator(calendar: calendar)
        self.goalProvider = { trainingGoalProvider().legacySwimGoal }
        self.trainingGoalProvider = trainingGoalProvider
        self.calendar = calendar
    }

    public func build(now: Date = Date()) async throws -> AthleteStateReading {
        let today = calendar.startOfDay(for: now)
        let workoutStart = calendar.date(byAdding: .day, value: -(Self.workoutWindowDays - 1), to: today) ?? today
        let vitalsStart = calendar.date(byAdding: .day, value: -(Self.vitalsWindowDays - 1), to: today) ?? today

        let allWorkouts = try await fetchWorkouts(workoutStart)
        let workouts = allWorkouts.compactMap(SwimWorkout.init(workout:))

        // Ohne Erholungswerte gibt es trotzdem einen Plan (Status unknown); ohne Workouts nicht,
        // denn dann wäre der Snapshot falsch statt nur unvollständig.
        var vitals: [DailyVitals] = []
        var vitalsAvailable = true
        do {
            vitals = try await vitalsRepository.fetchDailyVitals(from: vitalsStart)
        } catch {
            vitalsAvailable = false
        }

        // Einmal lesen, damit v1-Felder und v2-Teil sicher zum selben Ziel gehören.
        let trainingGoal = trainingGoalProvider?()
        var snapshot = calculator.snapshot(
            workouts: workouts, vitals: vitals, goal: trainingGoal?.legacySwimGoal ?? goalProvider(), now: now
        )
        if let trainingGoal {
            snapshot = MultiSportStateCalculator(calendar: calendar)
                .extend(snapshot, workouts: allWorkouts, goal: trainingGoal, now: now)
        }
        let cleaned = SwimWorkoutDeduplicator.deduplicate(workouts)
            .filter { $0.startDate <= now }
            .sorted { $0.startDate > $1.startDate }
        let cleanedAll = WorkoutDeduplicator.deduplicate(allWorkouts)
            .filter { $0.startDate <= now }
            .sorted { $0.startDate > $1.startDate }
        return AthleteStateReading(
            snapshot: snapshot,
            workouts: cleaned,
            allWorkouts: cleanedAll,
            vitalsAvailable: vitalsAvailable
        )
    }
}
