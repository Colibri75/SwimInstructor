import Foundation

/// Ein Nebenwettkampf neben dem Ziel, z. B. ein 10-km-Lauf auf dem Weg zum Triathlon. Das Ziel bleibt der
/// Hauptwettkampf; der Coach plant am Tag selbst kein Training und bremst die Tage davor und danach (siehe Server,
/// `secondaryRaces.ts`). Geht ohne Freitext zum Server (Snapshot v2, `training_goal.secondary_races`).
public struct SecondaryRace: Codable, Equatable, Sendable, Identifiable {
    /// Wie wichtig der Nebenwettkampf ist. Der Raw-Wert geht zum Server und darf nicht umbenannt werden.
    public enum Priority: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Mit kurzem Zuspitzen: die 3 Tage davor weniger, die 2 Tage danach locker.
        case b
        /// Als harte Einheit: nur der Tag davor und danach höchstens mittel.
        case c

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .b: return String(localized: "Mit kurzem Zuspitzen")
            case .c: return String(localized: "Als harte Einheit")
            }
        }

        public var explanation: String {
            switch self {
            case .b: return String(localized: "Die 3 Tage davor trainierst du weniger, die 2 Tage danach nur locker.")
            case .c: return String(localized: "Der Wettkampf zählt wie eine harte Einheit, der Tag davor und danach bleiben ruhiger.")
            }
        }
    }

    public var id: UUID
    /// Mittag (Berlin) des Wettkampftags, siehe `AthleteGoal.targetDate(onDayOf:)`.
    public var date: Date
    public var priority: Priority
    /// Sportart und Strecke; Zielzeit und Freiwasser zählen hier nicht.
    public var disciplines: [TrainingGoal.Discipline]

    public init(id: UUID = UUID(), date: Date, priority: Priority = .b, disciplines: [TrainingGoal.Discipline]) {
        self.id = id
        self.date = date
        self.priority = priority
        self.disciplines = disciplines
    }

    /// Höchstens so viele Nebenwettkämpfe.
    public static let maximumCount = 5
    /// So lange nach dem Wettkampf geht er noch zum Server (die Tage danach sind gebremst).
    public static let recoveryDays = 2

    public func discipline(for sport: SportID) -> TrainingGoal.Discipline? {
        disciplines.first { $0.sport == sport }
    }

    /// Setzt die Strecke einer Sportart oder nimmt sie heraus (`nil`). Die letzte Disziplin bleibt.
    public func settingDiscipline(_ discipline: TrainingGoal.Discipline?, for sport: SportID, registry: SportRegistry = .standard) -> SecondaryRace {
        var copy = self
        if let discipline {
            if let index = copy.disciplines.firstIndex(where: { $0.sport == sport }) {
                copy.disciplines[index] = discipline
            } else {
                copy.disciplines.append(discipline)
                copy.disciplines.sort { (registry.ids.firstIndex(of: $0.sport) ?? .max) < (registry.ids.firstIndex(of: $1.sport) ?? .max) }
            }
        } else if copy.disciplines.count > 1 {
            copy.disciplines.removeAll { $0.sport == sport }
        }
        return copy
    }

    /// Was nicht passt, auf Deutsch; `nil`, wenn er gültig ist.
    public func problem(registry: SportRegistry = .standard) -> String? {
        guard !disciplines.isEmpty else { return String(localized: "Ein Nebenwettkampf braucht mindestens eine Disziplin.") }
        guard Set(disciplines.map(\.sport)).count == disciplines.count else { return String(localized: "Jede Sportart darf nur einmal im Ziel stehen.") }
        for discipline in disciplines {
            guard let module = registry.module(for: discipline.sport) else {
                let sport = discipline.sport.rawValue
                return String(localized: "Unbekannte Sportart \(sport).")
            }
            guard TrainingGoal.distanceRange.contains(discipline.distanceMeters) else {
                let name = module.displayName
                return String(localized: "\(name): Die Strecke muss zwischen 100 m und 500 km liegen.")
            }
        }
        return nil
    }

    /// Kurzform für Listen: "Laufen 10,0 km" oder "Schwimmen 1500 m, Laufen 5,0 km".
    public func summary(registry: SportRegistry = .standard) -> String {
        disciplines.map { "\(registry.displayName(for: $0.sport)) \(PlanFormatting.distance($0.distanceMeters))" }.joined(separator: ", ")
    }
}

public extension TrainingGoal {
    /// Ein neuer Nebenwettkampf: in vier Wochen (aber vor dem Zieltag, wenn das geht), mit kurzem Zuspitzen, über
    /// die erste Disziplin des Ziels oder 5 km in der Sportart mit dem größten Schwerpunkt.
    func newSecondaryRace(now: Date, calendar: Calendar = .current) -> SecondaryRace {
        var day = calendar.date(byAdding: .day, value: 28, to: now) ?? now
        if kind != .fitness, day >= targetDate, let before = calendar.date(byAdding: .day, value: -7, to: targetDate), before > now {
            day = before
        }
        let taken = Set(secondaryRaces.map { calendar.startOfDay(for: $0.date) })
        while taken.contains(calendar.startOfDay(for: day)) || (kind != .fitness && calendar.isDate(day, inSameDayAs: targetDate)) {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        let discipline = disciplines.first.map { Discipline(sport: $0.sport, distanceMeters: $0.distanceMeters) }
            ?? Discipline(sport: emphasis.max(by: { $0.percent < $1.percent })?.sport ?? SportRegistry.standard.ids[0], distanceMeters: 5_000)
        return SecondaryRace(date: AthleteGoal.targetDate(onDayOf: day, calendar: calendar), disciplines: [discipline])
    }
}
