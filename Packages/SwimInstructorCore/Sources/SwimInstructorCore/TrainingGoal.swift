import Foundation

/// Die Art des Ziels (P2). Der Raw-Wert geht als `training_goal.kind` zum Server und darf nicht umbenannt werden.
public enum GoalKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Ein Wettkampf mit Disziplinen, je mit Zielzeit oder "Ankommen".
    case race
    /// Eine Zeit über eine Strecke ohne Wettkampf, z. B. 1500 m Kraul unter 30 Minuten.
    case time
    /// Eine Strecke am Stück schaffen, ohne Wettkampf und ohne Zielzeit.
    case distance
    /// Fit werden und bleiben: keine Disziplin, kein Wettkampf, der Zieltag ist nur das Ende des Planungszeitraums.
    case fitness

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .race: return "Wettkampf"
        case .time: return "Zeit über eine Strecke"
        case .distance: return "Strecke schaffen"
        case .fitness: return "Fit werden und bleiben"
        }
    }

    public var explanation: String {
        switch self {
        case .race: return "Ein Wettkampf an einem festen Tag, je Disziplin mit Zielzeit oder nur ankommen."
        case .time: return "Eine Zeit über eine Strecke ohne Wettkampf, z. B. 1500 m Kraul unter 30 Minuten. Am Zieltag steht ein eigener Versuch."
        case .distance: return "Eine Strecke am Stück schaffen, z. B. 3000 m schwimmen oder 10 km laufen, ohne Wettkampf."
        case .fitness: return "Ohne Zieltag: Der Plan steigert bis zu deiner Zeit im Wochenraster und hält sie dann."
        }
    }

    /// Ziele mit Disziplinen (alle außer Fitness).
    public var hasDisciplines: Bool { self != .fitness }
}

/// Das Gesamtziel über alle Sportarten: welcher Wettkampf (Disziplinen mit Strecke und optional Zielzeit), wann,
/// wie viel Zeit fürs Training bleibt und wie das Training auf die Sportarten verteilt sein soll.
///
/// Alles ist frei einstellbar; die Vorlagen (`GoalTemplate`) füllen nur vor. Das Ziel geht ohne Freitext zum Server
/// (Snapshot v2, `training_goal`).
public struct TrainingGoal: Codable, Equatable, Sendable {
    /// Eine Disziplin des Wettkampfs, z. B. 1500 m Schwimmen in 30 Minuten.
    public struct Discipline: Codable, Equatable, Sendable, Identifiable {
        public var sport: SportID
        public var distanceMeters: Double
        /// `nil`: ankommen ohne Zielzeit.
        public var targetDurationSeconds: TimeInterval?

        public var id: SportID { sport }

        public init(sport: SportID, distanceMeters: Double, targetDurationSeconds: TimeInterval? = nil) {
            self.sport = sport
            self.distanceMeters = distanceMeters
            self.targetDurationSeconds = targetDurationSeconds
        }
    }

    /// Anteil einer Sportart am Training in Prozent; alle zusammen ergeben 100.
    public struct Emphasis: Codable, Equatable, Sendable {
        public var sport: SportID
        public var percent: Int

        public init(sport: SportID, percent: Int) {
            self.sport = sport
            self.percent = percent
        }
    }

    /// Kennung der Vorlage, aus der das Ziel stammt; `nil` bei einem eigenen Ziel.
    public var template: String?
    /// Fehlt in Zielen von vor P2: dann ein Wettkampf.
    public var kind: GoalKind
    public var disciplines: [Discipline]
    /// Mittag (Berlin) des Zieltags, siehe `AthleteGoal.targetDate(onDayOf:)`. Bei einem Fitnessziel das Ende des
    /// Planungszeitraums.
    public var targetDate: Date
    /// Seit P2 aus dem Wochenraster (`WeeklySchedule.applied(to:)`).
    public var trainingDaysPerWeek: Int
    public var weeklyHours: Double
    public var emphasis: [Emphasis]

    public init(
        template: String? = nil,
        kind: GoalKind = .race,
        disciplines: [Discipline],
        targetDate: Date,
        trainingDaysPerWeek: Int,
        weeklyHours: Double,
        emphasis: [Emphasis]
    ) {
        self.template = template
        self.kind = kind
        self.disciplines = disciplines
        self.targetDate = targetDate
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.weeklyHours = weeklyHours
        self.emphasis = emphasis
    }

    private enum CodingKeys: String, CodingKey {
        case template, kind, disciplines, targetDate, trainingDaysPerWeek, weeklyHours, emphasis
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        template = try container.decodeIfPresent(String.self, forKey: .template)
        kind = try container.decodeIfPresent(GoalKind.self, forKey: .kind) ?? .race
        disciplines = try container.decode([Discipline].self, forKey: .disciplines)
        targetDate = try container.decode(Date.self, forKey: .targetDate)
        trainingDaysPerWeek = try container.decode(Int.self, forKey: .trainingDaysPerWeek)
        weeklyHours = try container.decode(Double.self, forKey: .weeklyHours)
        emphasis = try container.decode([Emphasis].self, forKey: .emphasis)
    }

    // MARK: - Grenzen

    public static let distanceRange: ClosedRange<Double> = 100...500_000
    public static let trainingDaysRange: ClosedRange<Int> = 1...7
    public static let weeklyHoursRange: ClosedRange<Double> = 1...30
    public static let maximumDisciplines = 8
    /// So weit reicht der Planungszeitraum eines neuen Fitnessziels.
    public static let fitnessHorizonWeeks = 26

    /// Der Anteil einer Sportart am Training (0, wenn sie nicht vorkommt).
    public func percent(for sport: SportID) -> Int {
        emphasis.first { $0.sport == sport }?.percent ?? 0
    }

    public func discipline(for sport: SportID) -> Discipline? {
        disciplines.first { $0.sport == sport }
    }

    /// Was am Ziel nicht passt, auf Deutsch; `nil`, wenn es gültig ist. Ohne den Zieltag: Ein gespeichertes Ziel
    /// bleibt gültig, wenn sein Tag vorbei ist (der Plan sagt dann, dass ein neues fällig ist).
    public func problem(registry: SportRegistry = .standard) -> String? {
        if kind.hasDisciplines {
            guard !disciplines.isEmpty else { return "Das Ziel braucht mindestens eine Disziplin." }
            if kind == .time, disciplines.contains(where: { $0.targetDurationSeconds == nil }) {
                return "Bei einer Zeit über eine Strecke braucht jede Disziplin eine Zielzeit."
            }
        } else {
            guard disciplines.isEmpty else { return "Ein Fitnessziel hat keine Disziplinen." }
        }
        guard disciplines.count <= Self.maximumDisciplines else { return "Höchstens \(Self.maximumDisciplines) Disziplinen." }
        guard Set(disciplines.map(\.sport)).count == disciplines.count else { return "Jede Sportart darf nur einmal im Ziel stehen." }
        for discipline in disciplines {
            guard let module = registry.module(for: discipline.sport) else { return "Unbekannte Sportart \(discipline.sport)." }
            guard Self.distanceRange.contains(discipline.distanceMeters) else {
                return "\(module.displayName): Die Strecke muss zwischen 100 m und 500 km liegen."
            }
            if let duration = discipline.targetDurationSeconds,
               !registry.isPlausibleGoal(sport: discipline.sport, distanceMeters: discipline.distanceMeters, durationSeconds: duration) {
                return "\(module.displayName): Strecke und Zielzeit ergeben ein unrealistisches Tempo."
            }
        }
        guard Self.trainingDaysRange.contains(trainingDaysPerWeek) else { return "Trainingstage: 1 bis 7 pro Woche." }
        guard Self.weeklyHoursRange.contains(weeklyHours) else { return "Trainingszeit: 1 bis 30 Stunden pro Woche." }
        guard !emphasis.isEmpty, Set(emphasis.map(\.sport)).count == emphasis.count else {
            return "Jede Sportart braucht genau einen Schwerpunkt."
        }
        guard emphasis.allSatisfy({ registry.module(for: $0.sport) != nil && (0...100).contains($0.percent) }) else {
            return "Schwerpunkte gehen von 0 bis 100 % und nur für bekannte Sportarten."
        }
        guard emphasis.reduce(0, { $0 + $1.percent }) == 100 else { return "Die Schwerpunkte müssen zusammen 100 % ergeben." }
        for discipline in disciplines where percent(for: discipline.sport) == 0 {
            return "\(registry.displayName(for: discipline.sport)) gehört zum Ziel und braucht einen Schwerpunkt über 0 %."
        }
        return nil
    }

    /// Wie `problem(registry:)`, dazu muss der Zieltag nach heute liegen (beim Einstellen eines neuen Ziels).
    public func problem(now: Date, calendar: Calendar = .current, registry: SportRegistry = .standard) -> String? {
        if let problem = problem(registry: registry) { return problem }
        guard calendar.startOfDay(for: targetDate) > calendar.startOfDay(for: now) else {
            return "Der Zieltag muss in der Zukunft liegen."
        }
        return nil
    }

    // MARK: - Bearbeiten

    /// Die Sportarten des Ziels: alle mit Schwerpunkt über 0, in der Reihenfolge der Registry.
    public var sports: [SportID] {
        emphasis.filter { $0.percent > 0 }.map(\.sport).sorted { order(of: $0) < order(of: $1) }
    }

    /// Wechselt die Zielart. Ein Fitnessziel verliert die Disziplinen und läuft `fitnessHorizonWeeks` Wochen ab `now`;
    /// ein Ziel mit Disziplinen bekommt, falls es keine hat, eine für die Sportart mit dem größten Schwerpunkt.
    /// "Strecke schaffen" hat keine Zielzeiten.
    public func settingKind(_ newKind: GoalKind, now: Date) -> TrainingGoal {
        var copy = self
        copy.kind = newKind
        copy.template = newKind == kind ? template : nil
        if newKind.hasDisciplines {
            if copy.disciplines.isEmpty, let sport = emphasis.max(by: { $0.percent < $1.percent })?.sport {
                copy.disciplines = [Discipline(sport: sport, distanceMeters: 5_000)]
            }
            if newKind == .distance {
                copy.disciplines = copy.disciplines.map { Discipline(sport: $0.sport, distanceMeters: $0.distanceMeters) }
            }
        } else {
            copy.disciplines = []
            if kind.hasDisciplines {
                copy.targetDate = AthleteGoal.targetDate(onDayOf: now.addingTimeInterval(TimeInterval(Self.fitnessHorizonWeeks * 7 * 86_400)))
            }
        }
        return copy
    }

    /// Nimmt eine Sportart ins Ziel (mit gleichem Anteil wie die anderen) oder heraus (mit ihrer Disziplin). Die letzte
    /// Sportart bleibt.
    public func settingSport(_ sport: SportID, included: Bool) -> TrainingGoal {
        if included {
            guard percent(for: sport) == 0 else { return self }
            return settingEmphasis(100 / (sports.count + 1), for: sport)
        }
        guard percent(for: sport) > 0, sports.count > 1 else { return self }
        var copy = settingDiscipline(nil, for: sport).settingEmphasis(0, for: sport)
        copy.emphasis.removeAll { $0.sport == sport }
        return copy
    }

    /// Setzt den Anteil einer Sportart und verteilt den Rest auf die anderen im Verhältnis ihrer bisherigen Anteile
    /// (alle gleich, wenn sie bisher zusammen 0 hatten). Die Summe bleibt 100.
    public func settingEmphasis(_ percent: Int, for sport: SportID) -> TrainingGoal {
        let value = min(max(percent, 0), 100)
        var others = emphasis.filter { $0.sport != sport }
        let remaining = 100 - value
        let previous = others.reduce(0) { $0 + $1.percent }
        if !others.isEmpty {
            var assigned = 0
            for index in others.indices {
                let share = previous > 0
                    ? Double(others[index].percent) / Double(previous)
                    : 1 / Double(others.count)
                others[index].percent = Int((Double(remaining) * share).rounded(.down))
                assigned += others[index].percent
            }
            // Rundungsrest an die bisher größte (bei Gleichstand die erste), damit es genau 100 sind.
            if let largest = others.indices.max(by: { others[$0].percent < others[$1].percent }) {
                others[largest].percent += remaining - assigned
            }
        }
        var copy = self
        let ownValue = others.isEmpty ? 100 : value
        copy.emphasis = (others + [Emphasis(sport: sport, percent: ownValue)])
            .sorted { lhs, rhs in order(of: lhs.sport) < order(of: rhs.sport) }
        return copy
    }

    /// Nimmt eine Sportart als Disziplin auf (mit Strecke) oder heraus. Eine neue Disziplin bekommt einen
    /// Schwerpunkt, falls sie noch keinen hat.
    public func settingDiscipline(_ discipline: Discipline?, for sport: SportID) -> TrainingGoal {
        var copy = self
        copy.template = nil
        if let discipline {
            if let index = copy.disciplines.firstIndex(where: { $0.sport == sport }) {
                copy.disciplines[index] = discipline
            } else {
                copy.disciplines.append(discipline)
                copy.disciplines.sort { order(of: $0.sport) < order(of: $1.sport) }
            }
            if copy.percent(for: sport) == 0 {
                let share = 100 / (copy.disciplines.count)
                copy = copy.settingEmphasis(share, for: sport)
            }
        } else {
            copy.disciplines.removeAll { $0.sport == sport }
        }
        return copy
    }

    /// Reihenfolge der Registry, unbekannte Sportarten zuletzt.
    private func order(of sport: SportID) -> Int {
        SportRegistry.standard.ids.firstIndex(of: sport) ?? Int.max
    }
}
