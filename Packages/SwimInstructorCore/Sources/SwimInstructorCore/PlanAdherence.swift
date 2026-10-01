import Foundation

/// Wie ein Tag im Vergleich zum Plan ausgegangen ist.
public enum AdherenceOutcome: String, Equatable, Sendable {
    /// Training geplant, ungefähr der geplante Umfang geschwommen (75 bis 125 %).
    case followed
    /// Training geplant, deutlich weniger geschwommen.
    case shorter
    /// Training geplant, deutlich mehr geschwommen.
    case longer
    /// Training geplant, nicht geschwommen.
    case missed
    /// Ruhetag geplant, nicht geschwommen.
    case restKept
    /// Ruhetag geplant, trotzdem geschwommen.
    case restBroken
    /// Heute, noch nichts geschwommen: Der Tag ist nicht vorbei.
    case pending
}

public struct PlanAdherenceEntry: Identifiable, Equatable, Sendable {
    /// Der Tag als `yyyy-MM-dd` (wie im Plan).
    public let date: String
    public let plan: TrainingPlan
    public let plannedMeters: Int
    public let actualMeters: Double
    public let workoutCount: Int
    public let outcome: AdherenceOutcome

    public var id: String { date }

    public init(date: String, plan: TrainingPlan, plannedMeters: Int, actualMeters: Double, workoutCount: Int, outcome: AdherenceOutcome) {
        self.date = date
        self.plan = plan
        self.plannedMeters = plannedMeters
        self.actualMeters = actualMeters
        self.workoutCount = workoutCount
        self.outcome = outcome
    }
}

/// Zusammenfassung des Zeitraums: Wie viele geplante Einheiten und Ruhetage wurden eingehalten?
public struct PlanAdherenceSummary: Equatable, Sendable {
    /// Geplante Trainingstage, die schon vorbei sind (ohne `pending`).
    public let plannedTrainingDays: Int
    /// Davon Tage, an denen geschwommen wurde (egal wie viel).
    public let trainedDays: Int
    /// Geplante Ruhetage, die schon vorbei sind.
    public let restDays: Int
    /// Davon Ruhetage ohne Schwimmen.
    public let restDaysKept: Int

    public init(plannedTrainingDays: Int, trainedDays: Int, restDays: Int, restDaysKept: Int) {
        self.plannedTrainingDays = plannedTrainingDays
        self.trainedDays = trainedDays
        self.restDays = restDays
        self.restDaysKept = restDaysKept
    }
}

/// Legt gespeicherte Pläne neben die tatsächlich geschwommenen Einheiten.
public struct PlanAdherenceCalculator: Sendable {
    /// Ab 75 % bis 125 % des geplanten Umfangs gilt ein Tag als umgesetzt.
    public static let lowerTolerance = 0.75
    public static let upperTolerance = 1.25

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Ein Eintrag je Plan der letzten `days` Tage, **neuester zuerst**. Tage ohne gespeicherten
    /// Plan fehlen (die App war nicht offen, es gab nichts zu vergleichen).
    ///
    /// Eine Einheit ohne Streckenangabe zählt als geschwommen, aber mit 0 m: Der Umfang lässt sich
    /// dann nicht vergleichen, also gilt ein Trainingstag als umgesetzt.
    public func entries(plans: [PlanResponse], workouts: [SwimWorkout], days: Int = 28, now: Date) -> [PlanAdherenceEntry] {
        let todayKey = PlanFormatting.isoDay(now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        guard let oldest = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let oldestKey = PlanFormatting.isoDay(oldest, calendar: calendar)

        var workoutsByDay: [String: [SwimWorkout]] = [:]
        for workout in workouts {
            workoutsByDay[PlanFormatting.isoDay(workout.startDate, calendar: calendar), default: []].append(workout)
        }

        return plans
            .filter { $0.date >= oldestKey && $0.date <= todayKey }
            .map { response -> PlanAdherenceEntry in
                let swum = workoutsByDay[response.date] ?? []
                let meters = swum.reduce(0.0) { $0 + ($1.totalDistanceMeters ?? 0) }
                return PlanAdherenceEntry(
                    date: response.date,
                    plan: response.plan,
                    plannedMeters: response.plan.totalDistanceMeters,
                    actualMeters: meters,
                    workoutCount: swum.count,
                    outcome: outcome(for: response.plan, meters: meters, workoutCount: swum.count, isToday: response.date == todayKey)
                )
            }
            .sorted { $0.date > $1.date }
    }

    public func summary(of entries: [PlanAdherenceEntry]) -> PlanAdherenceSummary {
        var planned = 0, trained = 0, rest = 0, restKept = 0
        for entry in entries {
            switch entry.outcome {
            case .pending:
                continue
            case .followed, .shorter, .longer:
                planned += 1
                trained += 1
            case .missed:
                planned += 1
            case .restKept:
                rest += 1
                restKept += 1
            case .restBroken:
                rest += 1
            }
        }
        return PlanAdherenceSummary(plannedTrainingDays: planned, trainedDays: trained, restDays: rest, restDaysKept: restKept)
    }

    private func outcome(for plan: TrainingPlan, meters: Double, workoutCount: Int, isToday: Bool) -> AdherenceOutcome {
        let swamAnything = workoutCount > 0

        if plan.isRestDay {
            if swamAnything { return .restBroken }
            return isToday ? .pending : .restKept
        }

        guard swamAnything else { return isToday ? .pending : .missed }

        let planned = Double(plan.totalDistanceMeters)
        // Ohne Streckenangabe in Health oder ohne geplante Strecke lässt sich nichts vergleichen.
        guard planned > 0, meters > 0 else { return .followed }
        let ratio = meters / planned
        // Heute kann noch eine zweite Einheit folgen: Erst am Tagesende zählt "zu kurz".
        if ratio < Self.lowerTolerance { return isToday ? .pending : .shorter }
        if ratio > Self.upperTolerance { return .longer }
        return .followed
    }
}
