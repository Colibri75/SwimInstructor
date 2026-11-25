import Foundation

/// Zielprognose: Welche Zeit wäre heute über die Strecken des Ziels drin, und wie weit ist das von der Zielzeit weg?
/// Gerechnet aus dem Leistungsprofil (CSS-Pace, Schwellentempo), aus Bestzeiten und Tempo des Startniveaus und beim Rad
/// aus den Fahrten in Health. Eine grobe Schätzung mit Faustformeln, keine Vorhersage des Wettkampfs: Sie zeigt, wo
/// die meiste Zeit liegt. Reine Rechnung ohne SwiftUI.
public struct GoalForecast: Equatable, Sendable {
    /// Woraus die Zeit einer Disziplin geschätzt ist.
    public enum Basis: Equatable, Sendable {
        /// CSS-Pace in s/100 m.
        case criticalSwimSpeed(Double)
        /// Übliches Schwimmtempo aus dem Startniveau in s/100 m.
        case swimPace(Double)
        /// Schwellentempo Laufen in s/km.
        case thresholdPace(Double)
        /// Bestzeit aus dem Startniveau.
        case bestTime(meters: Int, seconds: Double)
        /// Übliches Lauftempo aus dem Startniveau in s/km.
        case runPace(Double)
        /// Schnitt der schnellsten längeren Radfahrten der letzten Wochen in km/h.
        case recentRides(Double)
        /// Durchschnittstempo Rad aus dem Startniveau in km/h.
        case rideSpeed(Double)

        public var text: String {
            switch self {
            case .criticalSwimSpeed(let pace):
                return String(localized: "Aus deiner CSS-Pace \(PlanFormatting.pace(pace)) /100 m")
            case .swimPace(let pace):
                return String(localized: "Aus deinem üblichen Tempo \(PlanFormatting.pace(pace)) /100 m")
            case .thresholdPace(let pace):
                return String(localized: "Aus deinem Schwellentempo \(PlanFormatting.pace(pace)) /km")
            case .bestTime(let meters, let seconds):
                return String(localized: "Aus deiner Bestzeit über \(PlanFormatting.distance(Double(meters))) (\(GoalForecast.clock(seconds)))")
            case .runPace(let pace):
                return String(localized: "Aus deinem üblichen Tempo \(PlanFormatting.pace(pace)) /km")
            case .recentRides(let speed):
                return String(localized: "Aus deinen schnellsten längeren Fahrten der letzten Wochen (\(GoalForecast.speed(speed)))")
            case .rideSpeed(let speed):
                return String(localized: "Aus deinem Durchschnittstempo \(GoalForecast.speed(speed))")
            }
        }
    }

    /// Eine Disziplin des Ziels mit Prognose und Zielzeit.
    public struct Discipline: Equatable, Sendable, Identifiable {
        public let sport: SportID
        public let distanceMeters: Double
        public let targetSeconds: Double?
        /// `nil`: Es fehlt ein Wert für die Schätzung.
        public let predictedSeconds: Double?
        public let basis: Basis?

        public var id: SportID { sport }

        public init(sport: SportID, distanceMeters: Double, targetSeconds: Double?, predictedSeconds: Double?, basis: Basis?) {
            self.sport = sport
            self.distanceMeters = distanceMeters
            self.targetSeconds = targetSeconds
            self.predictedSeconds = predictedSeconds
            self.basis = basis
        }

        /// Prognose minus Zielzeit in Sekunden: positiv = noch zu langsam.
        public var gapSeconds: Double? {
            guard let predictedSeconds, let targetSeconds else { return nil }
            return predictedSeconds - targetSeconds
        }

        /// Wie viel Prozent der Zielzeit-Geschwindigkeit heute schon da sind (100 = Ziel erreicht), für den Balken.
        public var progressPercent: Int? {
            guard let predictedSeconds, let targetSeconds, predictedSeconds > 0 else { return nil }
            return Int((min(targetSeconds / predictedSeconds, 1) * 100).rounded())
        }

        /// "Im Ziel", "Fast da" oder "Noch 4 min".
        public var verdict: String? {
            guard let gap = gapSeconds, let targetSeconds else { return nil }
            if gap <= 0 { return String(localized: "Zielzeit schon drin") }
            if gap <= targetSeconds * GoalForecaster.almostThereShare { return String(localized: "Fast da") }
            return String(localized: "Noch \(GoalForecast.gap(gap))")
        }
    }

    public let disciplines: [Discipline]
    /// Geschätzte Wechselzeit bei einem Wettkampf mit mehreren Disziplinen, sonst `nil`.
    public let transitionSeconds: Double?

    public init(disciplines: [Discipline], transitionSeconds: Double?) {
        self.disciplines = disciplines
        self.transitionSeconds = transitionSeconds
    }

    /// Gesamtzeit, wenn jede Disziplin eine Prognose hat.
    public var predictedTotal: Double? {
        guard !disciplines.isEmpty, disciplines.allSatisfy({ $0.predictedSeconds != nil }) else { return nil }
        return disciplines.reduce(transitionSeconds ?? 0) { $0 + ($1.predictedSeconds ?? 0) }
    }

    /// Zielzeit gesamt, wenn jede Disziplin eine hat (Wechsel eingerechnet wie in der Prognose).
    public var targetTotal: Double? {
        guard !disciplines.isEmpty, disciplines.allSatisfy({ $0.targetSeconds != nil }) else { return nil }
        return disciplines.reduce(transitionSeconds ?? 0) { $0 + ($1.targetSeconds ?? 0) }
    }

    public var totalGap: Double? {
        guard let predictedTotal, let targetTotal else { return nil }
        return predictedTotal - targetTotal
    }

    /// Die Disziplin mit dem größten Rückstand auf die Zielzeit (nur, wenn es einen gibt).
    public var largestGap: Discipline? {
        disciplines.filter { ($0.gapSeconds ?? 0) > 0 }.max { ($0.gapSeconds ?? 0) < ($1.gapSeconds ?? 0) }
    }

    /// Ein Satz zur Prognose, für die Karte und "Weg zum Ziel".
    public func sentence(registry: SportRegistry = .standard) -> String {
        if let totalGap, let targetTotal {
            if totalGap <= 0 { return String(localized: "Deine Zielzeit ist heute schon drin. Jetzt geht es darum, fit an den Start zu kommen.") }
            if totalGap <= targetTotal * GoalForecaster.almostThereShare {
                return String(localized: "Du bist nah an deiner Zielzeit. Mit dem Plan bis zum Zieltag ist sie gut erreichbar.")
            }
        }
        if let largest = largestGap {
            return String(localized: "Am meisten Zeit holst du beim \(registry.displayName(for: largest.sport)).")
        }
        if disciplines.contains(where: { $0.predictedSeconds == nil }) {
            return String(localized: "Für eine Prognose fehlen noch Leistungswerte. Trag sie im Leistungsprofil ein oder mach einen Test.")
        }
        return String(localized: "Die Prognose zeigt, was heute ungefähr drin wäre.")
    }

    /// 5_490 → "1:31:30", 1_780 → "29:40".
    public static func clock(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// Abstand: unter einer Minute in Sekunden, sonst in Minuten ("40 s", "4 min", "1:12 h").
    public static func gap(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        guard total >= 60 else { return "\(max(total, 0)) s" }
        return PlanV2Formatting.duration(minutes: Double(total) / 60)
    }

    /// 31.4 → "31,4 km/h".
    public static func speed(_ kilometersPerHour: Double) -> String {
        String(format: "%.1f km/h", locale: AppLocale.current, kilometersPerHour)
    }
}

/// Rechnet `GoalForecast` für Wettkampf-, Zeit- und Streckenziele; beim Fitnessziel gibt es keine Prognose.
public struct GoalForecaster: Sendable {
    /// Bis zu so viel über der Zielzeit gilt als "fast da".
    public static let almostThereShare = 0.03
    /// Riegel-Exponent: Zeit wächst mit der Strecke hoch 1,06.
    static let riegel = 1.06
    /// Radfahrten so weit zurück zählen.
    static let rideWindowDays = 56
    /// Nur Fahrten ab so vielen Minuten zählen fürs Tempo.
    static let minimumRideMinutes = 45.0
    /// Übliches Lauftempo im Training gegen Schwellentempo.
    static let easyToThresholdFactor = 1.15

    public let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// `value(sport, metric)`: der gültige Leistungswert (`PerformanceProfileLoader.current`).
    public func forecast(
        goal: TrainingGoal,
        value: (SportID, PerformanceMetric) -> Double?,
        startingLevels: [StartingLevel],
        workouts: [Workout],
        now: Date
    ) -> GoalForecast? {
        guard goal.kind != .fitness, !goal.disciplines.isEmpty else { return nil }
        let isMultisport = goal.kind == .race && goal.disciplines.count > 1
        let disciplines = goal.disciplines.enumerated().map { index, discipline -> GoalForecast.Discipline in
            let level = startingLevels.first { $0.sport == discipline.sport }
            let estimate = self.estimate(
                discipline, before: Array(goal.disciplines[..<index]), isMultisport: isMultisport,
                value: value, level: level, workouts: workouts, now: now
            )
            return GoalForecast.Discipline(
                sport: discipline.sport,
                distanceMeters: discipline.distanceMeters,
                targetSeconds: discipline.targetDurationSeconds,
                predictedSeconds: estimate.map { $0.0.rounded() },
                basis: estimate?.1
            )
        }

        let transitions: Double?
        if isMultisport {
            let racing = disciplines.compactMap(\.predictedSeconds).reduce(0, +)
            transitions = racing < 2 * 3600 ? 180 : racing < 4 * 3600 ? 300 : racing < 8 * 3600 ? 480 : 720
        } else {
            transitions = nil
        }
        return GoalForecast(disciplines: disciplines, transitionSeconds: transitions)
    }
}
