import Foundation

/// Änderungen des Athleten an den 14 Tagen in Plan v2: Tag ohne Zeit, Ruhetag, Umfang einer Einheit, Sportart
/// tauschen, Einheit dazu, Tage tauschen, Verpasstes verschieben. Reine Funktionen ohne Speicher und ohne Server; danach
/// kann "Nächste 14 Tage neu planen" die Woche wieder ins Gleichgewicht bringen.
public enum MultiSportWeekEditor {
    /// Höchstens so viele Einheiten an einem Tag, wie beim Server.
    public static let maxSessionsPerDay = 2

    /// Bereich für den Umfang einer Einheit von Hand.
    public static func manualRange(for unit: PlanUnit) -> ClosedRange<Double> {
        switch unit {
        case .meters: return 0...6000
        case .minutes: return 0...360
        }
    }

    /// Schrittweite beim Ändern von Hand.
    public static func amountStep(for unit: PlanUnit) -> Double {
        switch unit {
        case .meters: return 100
        case .minutes: return 5
        }
    }

    // MARK: - Tage

    /// An diesem Tag ist keine Zeit: Er wird Ruhetag, das Geplante wird gemerkt.
    public static func markUnavailable(_ plan: WeekPlanV2, date: String) -> WeekPlanV2 {
        update(plan, date) { day in
            guard !day.isUnavailable else { return }
            day.contentBeforeUnavailable = day.isRestDay ? nil : day.content
            day.content = .rest(focus: "Keine Zeit")
            day.isUnavailable = true
            day.isEdited = true
        }
    }

    /// Doch wieder Zeit: Das gemerkte Training kommt zurück. Gab es keines, bleibt es ein Ruhetag.
    public static func clearUnavailable(_ plan: WeekPlanV2, date: String) -> WeekPlanV2 {
        update(plan, date) { day in
            guard day.isUnavailable else { return }
            day.content = day.contentBeforeUnavailable ?? .rest()
            day.contentBeforeUnavailable = nil
            day.isUnavailable = false
            // Das Training von vorher kommt zurück; der Coach darf den Tag wieder abstimmen.
            day.isEdited = false
        }
    }

    public static func setRest(_ plan: WeekPlanV2, date: String) -> WeekPlanV2 {
        update(plan, date) { day in
            guard !day.isUnavailable, !day.isRestDay else { return }
            day.content = .rest()
            day.isEdited = true
        }
    }

    /// Zwei Tage tauschen ihren Inhalt. Tage ohne Zeit bleiben, wie sie sind.
    public static func swap(_ plan: WeekPlanV2, _ first: String, _ second: String) -> WeekPlanV2 {
        guard first != second else { return plan }
        let base = ensureDay(ensureDay(plan, first), second)
        guard let a = base.day(on: first), let b = base.day(on: second), !a.isUnavailable, !b.isUnavailable else { return plan }
        let swapped = update(base, first) { day in
            day.content = b.content
            day.isEdited = true
        }
        return update(swapped, second) { day in
            day.content = a.content
            day.isEdited = true
        }
    }

    /// Verpasstes auf einen Ruhetag verschieben: Der Zieltag übernimmt die Einheiten, der Ursprungstag wird Ruhetag
    /// "Verschoben". Der Zieltag muss ein Ruhetag sein, damit nichts verloren geht.
    public static func moveToRestDay(_ plan: WeekPlanV2, from source: String, to target: String) -> WeekPlanV2 {
        guard source != target,
              let from = plan.day(on: source), !from.isRestDay,
              let destination = plan.day(on: target), destination.isRestDay, !destination.isUnavailable
        else { return plan }
        let placed = update(plan, target) { day in
            day.content = from.content
            day.isEdited = true
        }
        return update(placed, source) { day in
            day.content = .rest(focus: "Verschoben")
            day.isEdited = true
        }
    }

    // MARK: - Einheiten

    /// Umfang einer Einheit in ihrer Einheit (Meter oder Minuten). 0 streicht die Einheit; Dauer und Strecke ändern sich
    /// im selben Verhältnis. An Tagen ohne Zeit passiert nichts.
    public static func setAmount(_ plan: WeekPlanV2, date: String, session index: Int, amount: Double, registry: SportRegistry = .standard) -> WeekPlanV2 {
        update(plan, date) { day in
            guard !day.isUnavailable, day.sessions.indices.contains(index) else { return }
            let session = day.sessions[index]
            let clamped = min(max(amount, 0), manualRange(for: session.unit).upperBound)
            guard clamped != session.amount else { return }
            if clamped == 0 {
                day.sessions.remove(at: index)
                if day.sessions.isEmpty { day.focus = "Ruhetag" }
            } else {
                day.sessions[index] = resized(session, to: clamped, registry: registry)
            }
            day.isEdited = true
        }
    }

    /// Eine Einheit streichen.
    public static func removeSession(_ plan: WeekPlanV2, date: String, session index: Int) -> WeekPlanV2 {
        update(plan, date) { day in
            guard !day.isUnavailable, day.sessions.indices.contains(index) else { return }
            day.sessions.remove(at: index)
            // Ohne die Einheit davor ist die übrige kein Koppeltraining mehr.
            if !day.sessions.isEmpty { day.sessions[0].brick = false }
            if day.sessions.isEmpty { day.focus = "Ruhetag" }
            day.isEdited = true
        }
    }

    /// Eine lockere Ausdauereinheit dazu (1000 m bzw. 30 Minuten), höchstens zwei Einheiten je Tag.
    public static func addSession(_ plan: WeekPlanV2, date: String, sport: SportID, registry: SportRegistry = .standard) -> WeekPlanV2 {
        guard let module = registry.module(for: sport) else { return plan }
        return update(plan, date) { day in
            guard !day.isUnavailable, day.sessions.count < maxSessionsPerDay else { return }
            let amount: Double = module.planUnit == .meters ? 1000 : 30
            let converted = convert(amount, unit: module.planUnit, speed: module.typicalSpeedMetersPerSecond)
            day.sessions.append(WeekSession(
                sport: sport, sessionType: .endurance, intensity: .easy, amount: amount, unit: module.planUnit,
                minutes: converted.minutes, distanceMeters: converted.meters, focus: "Locker"
            ))
            if day.sessions.count == 1 { day.focus = "\(module.displayName) locker" }
            day.isEdited = true
        }
    }

    /// Tauscht die Sportart einer Einheit, z. B. Laufen gegen Rad. Die Dauer bleibt, der Umfang wird in die Einheit der
    /// neuen Sportart umgerechnet. Ein Test gehört zu seiner Sportart: Er wird eine lockere Ausdauereinheit.
    public static func changeSport(_ plan: WeekPlanV2, date: String, session index: Int, to sport: SportID, registry: SportRegistry = .standard) -> WeekPlanV2 {
        guard let module = registry.module(for: sport) else { return plan }
        return update(plan, date) { day in
            guard !day.isUnavailable, day.sessions.indices.contains(index), day.sessions[index].sport != sport else { return }
            var session = day.sessions[index]
            let minutes = session.minutes > 0
                ? session.minutes
                : convert(session.amount, unit: session.unit, speed: speed(of: session.sport, registry: registry)).minutes
            let raw = module.planUnit == .meters ? minutes * 60 * module.typicalSpeedMetersPerSecond : minutes
            let amount = rounded(raw, unit: module.planUnit)
            let converted = convert(amount, unit: module.planUnit, speed: module.typicalSpeedMetersPerSecond)
            session.sport = sport
            session.unit = module.planUnit
            session.amount = amount
            session.minutes = converted.minutes
            session.distanceMeters = converted.meters
            // Drinnen und Freiwasser gehören zur alten Sportart, wenn die neue sie nicht kennt.
            if module.indoorEquipment == nil { session.indoor = false }
            if module.openWater == nil { session.openWater = false }
            if session.test != nil {
                session.test = nil
                session.sessionType = .endurance
                session.intensity = .easy
                session.focus = "Locker statt Leistungstest"
            }
            day.sessions[index] = session
            day.isEdited = true
        }
    }

    // MARK: - Neu planen

    /// Übernimmt neu geplante Tage: Tage vor `fromDate` bleiben (sie sind vorbei), ab `fromDate` gilt der neue Plan. Tage
    /// ohne Zeit, von Hand geänderte Tage und die Tage in `keep` (etwa heute, wenn es schon einen Tagesplan gibt) bleiben,
    /// wie sie sind. Mit `through` bleiben auch die Tage danach, die der neue Plan nicht kennt.
    public static func merge(existing: WeekPlanV2?, generated: WeekPlanV2, fromDate: String, through: String? = nil, keep: Set<String> = []) -> WeekPlanV2 {
        guard let existing, existing.weekStart == generated.weekStart else { return generated }
        let kept = existing.days.filter { day in
            day.date < fromDate || (through.map { day.date > $0 && generated.day(on: day.date) == nil } ?? false)
        }
        let incoming = generated.days.filter { $0.date >= fromDate }.map { day -> PlannedDay in
            if let old = existing.day(on: day.date), old.isUnavailable || old.isEdited || keep.contains(day.date) { return old }
            return day
        }
        return WeekPlanV2(
            weekStart: generated.weekStart,
            generatedAt: generated.generatedAt,
            rationale: generated.rationale,
            adjustments: generated.adjustments,
            wishes: generated.wishes,
            days: kept + incoming
        )
    }

    /// Gibt einen von Hand geänderten Tag an den Coach zurück: Beim nächsten Abstimmen plant er ihn wieder.
    public static func release(_ plan: WeekPlanV2, date: String) -> WeekPlanV2 {
        guard plan.day(on: date)?.isEdited == true else { return plan }
        return update(plan, date) { day in
            day.isEdited = false
        }
    }

    // MARK: - Intern

    /// Kein Eintrag für den Tag: Er wird als Ruhetag angelegt, damit sich jeder Tag der Woche ändern lässt.
    private static func ensureDay(_ plan: WeekPlanV2, _ date: String) -> WeekPlanV2 {
        guard plan.day(on: date) == nil else { return plan }
        var copy = plan
        copy.days.append(PlannedDay(date: date, content: .rest()))
        copy.days.sort { $0.date < $1.date }
        return copy
    }

    private static func update(_ plan: WeekPlanV2, _ date: String, _ change: (inout PlannedDay) -> Void) -> WeekPlanV2 {
        var copy = ensureDay(plan, date)
        guard let index = copy.days.firstIndex(where: { $0.date == date }) else { return copy }
        change(&copy.days[index])
        return copy
    }

    /// Dieselbe Einheit mit anderem Umfang; Dauer und Strecke im selben Verhältnis (sie stammen vom Server und kennen
    /// das Tempo des Athleten), ohne bisherigen Umfang mit dem typischen Tempo der Sportart.
    static func resized(_ session: WeekSession, to amount: Double, registry: SportRegistry) -> WeekSession {
        var copy = session
        if session.amount > 0 {
            let factor = amount / session.amount
            copy.minutes = (session.minutes * factor).rounded()
            copy.distanceMeters = (session.distanceMeters * factor).rounded()
        } else {
            let converted = convert(amount, unit: session.unit, speed: speed(of: session.sport, registry: registry))
            copy.minutes = converted.minutes
            copy.distanceMeters = converted.meters
        }
        copy.amount = amount
        return copy
    }

    /// Minuten und Meter zu einem Umfang mit dem Tempo `speed` in m/s.
    static func convert(_ amount: Double, unit: PlanUnit, speed: Double) -> (minutes: Double, meters: Double) {
        switch unit {
        case .meters: return ((amount / speed / 60).rounded(), amount)
        case .minutes: return (amount, (amount * 60 * speed).rounded())
        }
    }

    /// Auf die Schrittweite der Einheit gerundet, mindestens ein Schritt.
    static func rounded(_ amount: Double, unit: PlanUnit) -> Double {
        let increment = amountStep(for: unit)
        return max((amount / increment).rounded() * increment, increment)
    }

    /// Typisches Tempo der Sportart; für eine unbekannte Sportart ein mittleres.
    static func speed(of sport: SportID, registry: SportRegistry) -> Double {
        registry.module(for: sport)?.typicalSpeedMetersPerSecond ?? 2
    }
}
