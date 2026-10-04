import Foundation

/// Wie eine Zieländerung auf den Gesamtplan wirkt (P3).
public enum GoalChangeKind: Equatable, Sendable {
    /// Nichts, was den Gesamtplan betrifft (z. B. nur die Vorlage).
    case none
    /// Zielzeit, Ankommen statt Zielzeit, Schwerpunkte, Begleitsport, Zieltag um höchstens zwei Wochen: Der Gesamtplan
    /// bleibt, die Änderung fließt in die nächste Fortschreibung.
    case fineTuning
    /// Zielart, Zieldisziplin dazu oder weg, Strecke, Zieltag um mehr als zwei Wochen: neuer Gesamtplan, die laufende
    /// Woche bleibt.
    case newGoal
}

public extension TrainingGoal {
    /// Ab so vielen Tagen Verschiebung des Zieltags ist es ein neues Ziel.
    static let newGoalDayShiftDays = 14

    /// Wie der Wechsel von diesem Ziel zu `new` auf den Gesamtplan wirkt.
    func change(to new: TrainingGoal, calendar: Calendar = .current) -> GoalChangeKind {
        guard planKey(calendar: calendar) != new.planKey(calendar: calendar) else { return .none }
        if kind != new.kind { return .newGoal }
        // Auch für ungültige Entwürfe (doppelte Sportart): kein Absturz, die Prüfung des Ziels meldet es.
        let oldDistances = Dictionary(disciplines.map { ($0.sport, $0.distanceMeters) }, uniquingKeysWith: { first, _ in first })
        let newDistances = Dictionary(new.disciplines.map { ($0.sport, $0.distanceMeters) }, uniquingKeysWith: { first, _ in first })
        if oldDistances != newDistances { return .newGoal }
        let shift = calendar.dateComponents([.day], from: calendar.startOfDay(for: targetDate), to: calendar.startOfDay(for: new.targetDate)).day ?? 0
        if abs(shift) > Self.newGoalDayShiftDays { return .newGoal }
        return .fineTuning
    }
}

/// Was beim Übernehmen eines Ziels passiert ist.
public enum GoalApplyResult: Equatable, Sendable {
    case unchanged
    /// Übernommen, Gesamtplan bleibt (gleiche Zielversion).
    case fineTuned
    /// Übernommen, neue Zielversion: Der Gesamtplan wird neu erstellt.
    case newGoal
    /// Nicht übernommen: Die letzte Übernahme eines neuen Ziels ist keine 7 Tage her.
    case locked(until: Date)
    /// Nicht übernommen: Das Ziel ist ungültig.
    case invalid(String)
}
