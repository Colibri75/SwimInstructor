import Foundation

/// Eine Abstimmung der 14 Tage, die im Hintergrund unterwegs ist: was nach der Antwort gilt. Reist als Text in der
/// Übertragung mit, damit die Antwort auch ankommt, wenn iOS die App bis dahin beendet hat.
public struct BackgroundReplan: Codable, Equatable, Sendable {
    /// Erster geplanter Tag (heute bei der Anfrage).
    public let fromDate: String
    /// Letzter geplanter Tag.
    public let through: String
    /// Tage, die bei der Anfrage feststanden (von Hand geändert, heute schon geplant).
    public let keep: [String]
    public let reason: ReplanReason
    /// Der Anlass außer der Reihe (Beschwerden, harte Einheit, Ausfall), `nil` bei der täglichen Abstimmung.
    public let signalKey: String?
    /// Tag und Stand von Ziel und Gesamtplan; danach gilt die tägliche Abstimmung als erledigt.
    public let marker: String

    public init(fromDate: String, through: String, keep: [String], reason: ReplanReason, signalKey: String?, marker: String) {
        self.fromDate = fromDate
        self.through = through
        self.keep = keep
        self.reason = reason
        self.signalKey = signalKey
        self.marker = marker
    }
}

/// Was eine neue Abstimmung an den nächsten Tagen geändert hat, und warum: für die Mitteilung "Dein Coach hat deinen
/// Plan angepasst" und die Nachricht dahinter.
public struct PlanChangeReport: Codable, Equatable, Sendable {
    /// Ein Tag, der jetzt anders aussieht: "Laufen · 40 min" statt "Ruhetag".
    public struct DayChange: Codable, Equatable, Sendable {
        public let date: String
        public let before: String
        public let after: String

        public init(date: String, before: String, after: String) {
            self.date = date
            self.before = before
            self.after = after
        }
    }

    /// So viele Tage ab heute zählen für die Mitteilung; spätere Tage ändern sich bis dahin ohnehin noch.
    public static let noticeDays = 7
    /// Weicht ein Umfang um weniger als diesen Anteil ab, ist das keine Mitteilung wert.
    public static let amountTolerance = 0.15

    public let reason: ReplanReason
    /// Die Begründung deines Coachs für die nächsten Tage (in der Sprache der App).
    public let rationale: String
    public let changes: [DayChange]

    public init(reason: ReplanReason, rationale: String, changes: [DayChange]) {
        self.reason = reason
        self.rationale = rationale
        self.changes = changes
    }

    /// Ob es dafür eine Mitteilung gibt: bei einem Anlass außer der Reihe immer, bei der täglichen Abstimmung nur, wenn
    /// sich an den nächsten Tagen spürbar etwas geändert hat.
    public var isWorthTelling: Bool {
        PlanV2Formatting.adaptationNotice(reason) != nil || !changes.isEmpty
    }

    /// Vergleicht die nächsten Tage vor und nach der Abstimmung. Nur die ersten `noticeDays` Tage zählen, und nur, wenn
    /// Sportarten, Intensität oder Kraft und Mobilität andere sind oder ein Umfang spürbar abweicht.
    public static func make(
        dates: [String],
        before: [PlannedDay?],
        after: [PlannedDay?],
        reason: ReplanReason,
        rationale: String,
        registry: SportRegistry = .standard
    ) -> PlanChangeReport {
        var changes: [DayChange] = []
        for (index, date) in dates.prefix(noticeDays).enumerated() {
            let old = index < before.count ? before[index] : nil
            let new = index < after.count ? after[index] : nil
            // Ein Tag, den es vorher nicht gab, ist neu geplant, keine Änderung.
            guard let old, let new, differs(old, new) else { continue }
            changes.append(DayChange(
                date: date,
                before: summary(old, registry: registry),
                after: summary(new, registry: registry)
            ))
        }
        return PlanChangeReport(reason: reason, rationale: rationale, changes: changes)
    }

    /// "Laufen · 40 min, Kraft", "Ruhetag", "Mobilität" (Ruhetag mit Block), "keine Zeit".
    static func summary(_ day: PlannedDay, registry: SportRegistry) -> String {
        let extras = day.extras.map(\.kind.displayName)
        guard !day.isUnavailable, !extras.isEmpty else { return PlanV2Formatting.daySummary(day, registry: registry) }
        if day.sessions.isEmpty { return extras.joined(separator: ", ") }
        return ([PlanV2Formatting.daySummary(day, registry: registry)] + extras).joined(separator: ", ")
    }

    static func differs(_ old: PlannedDay, _ new: PlannedDay) -> Bool {
        if old.isUnavailable != new.isUnavailable { return true }
        if old.extras.map(\.kind) != new.extras.map(\.kind) { return true }
        guard old.sessions.count == new.sessions.count else { return true }
        for (a, b) in zip(old.sessions, new.sessions) {
            if a.sport != b.sport || a.intensity != b.intensity || a.unit != b.unit { return true }
            let larger = max(a.amount, b.amount)
            if larger > 0, abs(a.amount - b.amount) / larger >= amountTolerance { return true }
        }
        return false
    }
}
