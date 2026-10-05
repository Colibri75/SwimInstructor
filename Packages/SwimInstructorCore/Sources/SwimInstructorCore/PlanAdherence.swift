import Foundation

/// Wie ein Tag im Vergleich zum Plan ausgegangen ist.
public enum AdherenceOutcome: String, Equatable, Sendable {
    /// Training geplant, ungefähr der geplante Umfang umgesetzt (75 bis 125 %).
    case followed
    /// Training geplant, deutlich weniger gemacht.
    case shorter
    /// Training geplant, deutlich mehr gemacht.
    case longer
    /// Training geplant, nicht trainiert.
    case missed
    /// Ruhetag geplant, nicht trainiert.
    case restKept
    /// Ruhetag geplant, trotzdem trainiert.
    case restBroken
    /// Heute, noch nichts trainiert: Der Tag ist nicht vorbei.
    case pending
}

/// Zusammenfassung des Zeitraums: Wie viele geplante Einheiten und Ruhetage wurden eingehalten?
public struct PlanAdherenceSummary: Equatable, Sendable {
    /// Geplante Trainingstage, die schon vorbei sind (ohne `pending`).
    public let plannedTrainingDays: Int
    /// Davon Tage, an denen trainiert wurde (egal wie viel).
    public let trainedDays: Int
    /// Geplante Ruhetage, die schon vorbei sind.
    public let restDays: Int
    /// Davon Ruhetage ohne Training.
    public let restDaysKept: Int

    public init(plannedTrainingDays: Int, trainedDays: Int, restDays: Int, restDaysKept: Int) {
        self.plannedTrainingDays = plannedTrainingDays
        self.trainedDays = trainedDays
        self.restDays = restDays
        self.restDaysKept = restDaysKept
    }
}

/// Zählt Tage nach ihrem Ausgang (`MultiSportComparator` bestimmt ihn je Tag).
public enum PlanAdherenceCalculator {
    /// Zählt die Tage nach ihrem Ausgang; offene Tage (`pending`) zählen nicht.
    public static func summary(of outcomes: [AdherenceOutcome]) -> PlanAdherenceSummary {
        var planned = 0, trained = 0, rest = 0, restKept = 0
        for outcome in outcomes {
            switch outcome {
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
}
