import Foundation

/// Wie ein Tag der Woche im Vergleich zum Plan steht.
public enum WeekDayState: Equatable, Sendable {
    /// Kein Eintrag im Wochenplan (z. B. Tage vor dem Planen).
    case unplanned
    /// Geplant, noch nicht dran.
    case upcoming
    /// Heute, noch offen.
    case today
    /// Training geplant und ungefähr der geplante Umfang geschwommen (75 bis 125 %).
    case followed
    case shorter
    case longer
    /// Training geplant, nicht geschwommen.
    case missed
    case restKept
    /// Ruhetag geplant, trotzdem geschwommen.
    case restBroken
    /// Der Athlet hat an diesem Tag keine Zeit.
    case skipped
}
