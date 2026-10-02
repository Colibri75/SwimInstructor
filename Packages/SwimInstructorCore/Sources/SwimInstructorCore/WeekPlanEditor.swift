import Foundation

/// Änderungen des Athleten am Wochenplan: Tag ohne Zeit, tauschen, verschieben, Umfang. Reine
/// Funktionen ohne Speicher und ohne Server. Eine Änderung verschiebt nur Einheiten und rechnet nichts
/// nach; danach kann "Rest der Woche neu planen" die Woche wieder ins Gleichgewicht bringen.
public enum WeekPlanEditor {
    /// Obergrenze für den Umfang eines Tages von Hand.
    public static let maxDistanceMeters = 6000

    /// Kein Eintrag für den Tag: Er wird als Ruhetag angelegt, damit sich jeder Tag der Woche ändern lässt.
    private static func ensureDay(_ plan: WeekPlan, _ date: String) -> WeekPlan {
        guard plan.day(on: date) == nil else { return plan }
        var copy = plan
        copy.days.append(WeekDayPlan(date: date, content: .rest()))
        copy.days.sort { $0.date < $1.date }
        return copy
    }

    private static func update(_ plan: WeekPlan, _ date: String, _ change: (inout WeekDayPlan) -> Void) -> WeekPlan {
        var copy = ensureDay(plan, date)
        guard let index = copy.days.firstIndex(where: { $0.date == date }) else { return copy }
        change(&copy.days[index])
        return copy
    }

    /// An diesem Tag ist keine Zeit: Er wird Ruhetag, das Geplante wird gemerkt.
    public static func markUnavailable(_ plan: WeekPlan, date: String) -> WeekPlan {
        update(plan, date) { day in
            guard !day.isUnavailable else { return }
            day.contentBeforeUnavailable = day.isRestDay ? nil : day.content
            day.content = .rest(focus: "Keine Zeit")
            day.isUnavailable = true
            day.isEdited = true
        }
    }

    /// Doch wieder Zeit: Das gemerkte Training kommt zurück. Gab es keines, bleibt es ein Ruhetag.
    public static func clearUnavailable(_ plan: WeekPlan, date: String) -> WeekPlan {
        update(plan, date) { day in
            guard day.isUnavailable else { return }
            day.content = day.contentBeforeUnavailable ?? .rest()
            day.contentBeforeUnavailable = nil
            day.isUnavailable = false
            day.isEdited = true
        }
    }

    public static func setRest(_ plan: WeekPlan, date: String) -> WeekPlan {
        update(plan, date) { day in
            guard !day.isUnavailable else { return }
            day.content = .rest()
            day.isEdited = true
        }
    }

    /// Umfang eines Tages. 0 m macht den Tag zum Ruhetag; aus einem Ruhetag wird mit mehr als 0 m eine
    /// lockere Ausdauereinheit. Die Dauer folgt dem Umfang. An Tagen ohne Zeit passiert nichts.
    public static func setDistance(_ plan: WeekPlan, date: String, meters: Int) -> WeekPlan {
        let clamped = min(max(meters, 0), maxDistanceMeters)
        return update(plan, date) { day in
            guard !day.isUnavailable else { return }
            if clamped == 0 {
                day.content = .rest()
            } else if day.isRestDay {
                day.content = WeekDayContent(
                    sessionType: .endurance,
                    intensity: .easy,
                    targetDistanceMeters: clamped,
                    estimatedDurationMinutes: estimatedMinutes(forMeters: clamped),
                    focus: "Ausdauer"
                )
            } else {
                let old = max(day.targetDistanceMeters, 1)
                day.estimatedDurationMinutes = max(Int((Double(day.estimatedDurationMinutes) * Double(clamped) / Double(old)).rounded()), 5)
                day.targetDistanceMeters = clamped
            }
            day.isEdited = true
        }
    }

    /// Zwei Tage tauschen ihren Inhalt. Tage ohne Zeit bleiben, wie sie sind.
    public static func swap(_ plan: WeekPlan, _ first: String, _ second: String) -> WeekPlan {
        guard first != second else { return plan }
        let base = ensureDay(ensureDay(plan, first), second)
        guard let a = base.day(on: first), let b = base.day(on: second), !a.isUnavailable, !b.isUnavailable else { return plan }
        let contentA = a.content
        let contentB = b.content
        let swapped = update(base, first) { day in
            day.content = contentB
            day.isEdited = true
        }
        return update(swapped, second) { day in
            day.content = contentA
            day.isEdited = true
        }
    }

    /// Eine verpasste Einheit auf einen Ruhetag verschieben: Der Zieltag übernimmt sie, der Ursprungstag
    /// wird zum Ruhetag "Verschoben". Der Zieltag muss ein Ruhetag sein, sonst geht nichts verloren.
    public static func moveToRestDay(_ plan: WeekPlan, from source: String, to target: String) -> WeekPlan {
        guard source != target,
              let from = plan.day(on: source), !from.isRestDay,
              let destination = plan.day(on: target), destination.isRestDay, !destination.isUnavailable
        else { return plan }
        let moved = from.content
        let placed = update(plan, target) { day in
            day.content = moved
            day.isEdited = true
        }
        return update(placed, source) { day in
            day.content = .rest(focus: "Verschoben")
            day.isEdited = true
        }
    }

    /// Übernimmt einen neu geplanten Wochenplan: Tage vor `fromDate` bleiben, wie sie waren (sie sind
    /// vorbei), ab `fromDate` gilt der neue Plan. Tage ohne Zeit behalten ihre Markierung.
    ///
    /// Mit `through` (rollender Plan, der nur sieben Tage umfasst) bleiben auch die Tage nach diesem Datum,
    /// die der neue Plan nicht kennt, wie sie waren: Sie stammen aus dem Plan davor, bis ein späterer
    /// Lauf sie neu plant. Ohne `through` gilt ab `fromDate` nur noch der neue Plan.
    public static func merge(existing: WeekPlan?, generated: WeekPlan, fromDate: String, through: String? = nil) -> WeekPlan {
        guard let existing else { return generated }
        guard existing.weekStart == generated.weekStart else { return generated }

        let kept = existing.days.filter { day in
            day.date < fromDate || (through.map { day.date > $0 && generated.day(on: day.date) == nil } ?? false)
        }
        let incoming = generated.days.filter { $0.date >= fromDate }.map { day -> WeekDayPlan in
            if let old = existing.day(on: day.date), old.isUnavailable { return old }
            return day
        }
        return WeekPlan(
            weekStart: generated.weekStart,
            generatedAt: generated.generatedAt,
            rationale: generated.rationale,
            adjustments: generated.adjustments,
            wishes: generated.wishes,
            days: kept + incoming
        )
    }

    /// Dauer einer neu angelegten Einheit: rund zweieinhalb Minuten je 100 m inklusive Pausen.
    static func estimatedMinutes(forMeters meters: Int) -> Int {
        max(Int((Double(meters) / 100 * 2.5).rounded()), 5)
    }
}
