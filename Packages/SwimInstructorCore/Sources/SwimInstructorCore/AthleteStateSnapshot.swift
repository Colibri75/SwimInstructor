import Foundation

/// Warnhinweise, die Claude im Plan berücksichtigen soll. Die Raw-Werte sind Teil des
/// JSON-Schemas und dürfen nicht umbenannt werden.
public enum AthleteFlag: String, Codable, Sendable, CaseIterable {
    case trainingPause = "training_pause"
    case volumeSpike = "volume_spike"
    case recoveryPoor = "recovery_poor"
    case overreachingRisk = "overreaching_risk"
    case goalWithinFourWeeks = "goal_within_four_weeks"
}

public enum RecoveryStatus: String, Codable, Sendable {
    case good
    case moderate
    case poor
    case unknown
}

public enum RecoverySignal: String, Codable, Sendable {
    case elevatedRestingHeartRate = "elevated_resting_heart_rate"
    case lowHeartRateVariability = "low_heart_rate_variability"
    case shortSleep = "short_sleep"
}

/// Kompakter Zustands-Snapshot, der ans Backend und von dort an Claude geht.
///
/// Feldnamen bewusst ohne Ziffern, damit die snake_case-Umwandlung im JSON eindeutig ist.
/// Optionale Felder fehlen im JSON, wenn es keinen Wert gibt (z. B. keine Vergleichsdaten).
///
/// Schema v1 beschreibt nur das Schwimmen. v2 (Triathlon-Umbau) hängt Gesamtziel, Werte je Sportart und Gesamtlast an
/// und lässt alle v1-Felder unverändert; `version1` macht daraus wieder genau den v1-Snapshot.
public struct AthleteStateSnapshot: Codable, Equatable, Sendable {
    /// Die Version, die `AthleteStateCalculator` erzeugt (nur Schwimmen).
    public static let currentSchemaVersion = 1
    /// Die Version mit Gesamtziel und allen Sportarten (`withMultiSport`).
    public static let multiSportSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    public let goal: GoalSummary
    public let volume: VolumeSummary
    public let pace: PaceSummary
    public let load: LoadSummary
    public let recovery: RecoverySummary
    public let flags: [AthleteFlag]
    /// Ab v2: das Gesamtziel über alle Sportarten.
    public let trainingGoal: TrainingGoalSummary?
    /// Ab v2: Werte je Sportart (alle Sportarten mit Training oder Schwerpunkt, in der Reihenfolge der Registry).
    public let sports: [SportStateSummary]?
    /// Ab v2: Belastung über alle Sportarten.
    public let totalLoad: TotalLoadSummary?

    public init(
        schemaVersion: Int = AthleteStateSnapshot.currentSchemaVersion,
        generatedAt: Date,
        goal: GoalSummary,
        volume: VolumeSummary,
        pace: PaceSummary,
        load: LoadSummary,
        recovery: RecoverySummary,
        flags: [AthleteFlag],
        trainingGoal: TrainingGoalSummary? = nil,
        sports: [SportStateSummary]? = nil,
        totalLoad: TotalLoadSummary? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.goal = goal
        self.volume = volume
        self.pace = pace
        self.load = load
        self.recovery = recovery
        self.flags = flags
        self.trainingGoal = trainingGoal
        self.sports = sports
        self.totalLoad = totalLoad
    }

    /// Derselbe Snapshot als v2, mit Gesamtziel, Werten je Sportart und Gesamtlast.
    public func withMultiSport(
        trainingGoal: TrainingGoalSummary,
        sports: [SportStateSummary],
        totalLoad: TotalLoadSummary
    ) -> AthleteStateSnapshot {
        AthleteStateSnapshot(
            schemaVersion: Self.multiSportSchemaVersion,
            generatedAt: generatedAt, goal: goal, volume: volume, pace: pace, load: load, recovery: recovery, flags: flags,
            trainingGoal: trainingGoal, sports: sports, totalLoad: totalLoad
        )
    }

    /// Nur die v1-Felder, für einen Server, der v2 noch nicht kennt.
    public var version1: AthleteStateSnapshot {
        AthleteStateSnapshot(
            schemaVersion: Self.currentSchemaVersion,
            generatedAt: generatedAt, goal: goal, volume: volume, pace: pace, load: load, recovery: recovery, flags: flags
        )
    }

    public struct GoalSummary: Codable, Equatable, Sendable {
        public let distanceMeters: Double
        public let targetDurationSeconds: Double
        public let targetPaceSecondsPerHundredMeters: Double
        public let targetDate: Date
        public let daysUntilGoal: Int

        public init(
            distanceMeters: Double,
            targetDurationSeconds: Double,
            targetPaceSecondsPerHundredMeters: Double,
            targetDate: Date,
            daysUntilGoal: Int
        ) {
            self.distanceMeters = distanceMeters
            self.targetDurationSeconds = targetDurationSeconds
            self.targetPaceSecondsPerHundredMeters = targetPaceSecondsPerHundredMeters
            self.targetDate = targetDate
            self.daysUntilGoal = daysUntilGoal
        }
    }

    public struct VolumeSummary: Codable, Equatable, Sendable {
        public let lastSevenDaysMeters: Double
        /// Durchschnittliches Wochenvolumen der letzten vier Wochen.
        public let averageWeeklyMeters: Double
        /// Veränderung der letzten sieben Tage gegenüber der Woche davor in Prozent.
        public let weeklyChangePercent: Double?
        public let sessionsLastSevenDays: Int
        public let sessionsLastFourWeeks: Int
        /// Längste Einheit der letzten vier Wochen.
        public let longestSessionMeters: Double

        public init(
            lastSevenDaysMeters: Double,
            averageWeeklyMeters: Double,
            weeklyChangePercent: Double?,
            sessionsLastSevenDays: Int,
            sessionsLastFourWeeks: Int,
            longestSessionMeters: Double
        ) {
            self.lastSevenDaysMeters = lastSevenDaysMeters
            self.averageWeeklyMeters = averageWeeklyMeters
            self.weeklyChangePercent = weeklyChangePercent
            self.sessionsLastSevenDays = sessionsLastSevenDays
            self.sessionsLastFourWeeks = sessionsLastFourWeeks
            self.longestSessionMeters = longestSessionMeters
        }
    }

    public struct PaceSummary: Codable, Equatable, Sendable {
        /// Gewichtete Pace der letzten vier Wochen (Gesamtzeit durch Gesamtdistanz).
        public let recentPaceSecondsPerHundredMeters: Double?
        /// Gewichtete Pace der vier Wochen davor (Woche 5 bis 8).
        public let previousPaceSecondsPerHundredMeters: Double?
        /// Recent minus previous; negativ heißt schneller geworden.
        public let trendSecondsPerHundredMeters: Double?
        /// Recent minus Zielpace; positiv heißt noch zu langsam fürs Ziel.
        public let gapToTargetSecondsPerHundredMeters: Double?

        public init(
            recentPaceSecondsPerHundredMeters: Double?,
            previousPaceSecondsPerHundredMeters: Double?,
            trendSecondsPerHundredMeters: Double?,
            gapToTargetSecondsPerHundredMeters: Double?
        ) {
            self.recentPaceSecondsPerHundredMeters = recentPaceSecondsPerHundredMeters
            self.previousPaceSecondsPerHundredMeters = previousPaceSecondsPerHundredMeters
            self.trendSecondsPerHundredMeters = trendSecondsPerHundredMeters
            self.gapToTargetSecondsPerHundredMeters = gapToTargetSecondsPerHundredMeters
        }
    }

    public struct LoadSummary: Codable, Equatable, Sendable {
        public let daysSinceLastWorkout: Int?
        public let daysSinceLastHardSession: Int?

        public init(daysSinceLastWorkout: Int?, daysSinceLastHardSession: Int?) {
            self.daysSinceLastWorkout = daysSinceLastWorkout
            self.daysSinceLastHardSession = daysSinceLastHardSession
        }
    }

    public struct RecoverySummary: Codable, Equatable, Sendable {
        public let status: RecoveryStatus
        /// Ruhepuls der letzten drei Tage minus Baseline in bpm; positiv ist schlechter.
        public let restingHeartRateDeviationBpm: Double?
        /// HRV der letzten drei Tage gegenüber Baseline in Prozent; negativ ist schlechter.
        public let hrvDeviationPercent: Double?
        public let recentAverageSleepHours: Double?
        public let warningSignals: [RecoverySignal]

        public init(
            status: RecoveryStatus,
            restingHeartRateDeviationBpm: Double?,
            hrvDeviationPercent: Double?,
            recentAverageSleepHours: Double?,
            warningSignals: [RecoverySignal]
        ) {
            self.status = status
            self.restingHeartRateDeviationBpm = restingHeartRateDeviationBpm
            self.hrvDeviationPercent = hrvDeviationPercent
            self.recentAverageSleepHours = recentAverageSleepHours
            self.warningSignals = warningSignals
        }
    }
}

// MARK: - v2

public extension AthleteStateSnapshot {
    /// Das Gesamtziel über alle Sportarten, wie es zum Server geht (ohne Freitext).
    struct TrainingGoalSummary: Codable, Equatable, Sendable {
        public let template: String?
        public let targetDate: Date
        public let daysUntilGoal: Int
        public let trainingDaysPerWeek: Int
        public let weeklyHours: Double
        public let disciplines: [TrainingGoal.Discipline]
        public let emphasis: [TrainingGoal.Emphasis]

        public init(
            template: String?,
            targetDate: Date,
            daysUntilGoal: Int,
            trainingDaysPerWeek: Int,
            weeklyHours: Double,
            disciplines: [TrainingGoal.Discipline],
            emphasis: [TrainingGoal.Emphasis]
        ) {
            self.template = template
            self.targetDate = targetDate
            self.daysUntilGoal = daysUntilGoal
            self.trainingDaysPerWeek = trainingDaysPerWeek
            self.weeklyHours = weeklyHours
            self.disciplines = disciplines
            self.emphasis = emphasis
        }
    }

    /// Was in einer Sportart zuletzt trainiert wurde. Fenster wie bei v1: letzte 7 Tage (Tag 0 bis 6) und
    /// Wochenschnitt der letzten 4 Wochen (Tag 0 bis 27, geteilt durch 4).
    struct SportStateSummary: Codable, Equatable, Sendable {
        public let sport: SportID
        public let sessionsLastSevenDays: Int
        public let sessionsLastFourWeeks: Int
        public let minutesLastSevenDays: Double
        public let averageWeeklyMinutes: Double
        public let metersLastSevenDays: Double
        public let averageWeeklyMeters: Double
        public let longestSessionMeters: Double
        public let longestSessionMinutes: Double
        public let loadLastSevenDays: Double
        public let averageWeeklyLoad: Double
        public let daysSinceLastSession: Int?

        public init(
            sport: SportID,
            sessionsLastSevenDays: Int,
            sessionsLastFourWeeks: Int,
            minutesLastSevenDays: Double,
            averageWeeklyMinutes: Double,
            metersLastSevenDays: Double,
            averageWeeklyMeters: Double,
            longestSessionMeters: Double,
            longestSessionMinutes: Double,
            loadLastSevenDays: Double,
            averageWeeklyLoad: Double,
            daysSinceLastSession: Int?
        ) {
            self.sport = sport
            self.sessionsLastSevenDays = sessionsLastSevenDays
            self.sessionsLastFourWeeks = sessionsLastFourWeeks
            self.minutesLastSevenDays = minutesLastSevenDays
            self.averageWeeklyMinutes = averageWeeklyMinutes
            self.metersLastSevenDays = metersLastSevenDays
            self.averageWeeklyMeters = averageWeeklyMeters
            self.longestSessionMeters = longestSessionMeters
            self.longestSessionMinutes = longestSessionMinutes
            self.loadLastSevenDays = loadLastSevenDays
            self.averageWeeklyLoad = averageWeeklyLoad
            self.daysSinceLastSession = daysSinceLastSession
        }
    }

    /// Belastung über alle Sportarten (Last nach `TrainingLoadCalculator`).
    struct TotalLoadSummary: Codable, Equatable, Sendable {
        public let minutesLastSevenDays: Double
        public let averageWeeklyMinutes: Double
        public let loadLastSevenDays: Double
        public let averageWeeklyLoad: Double
        /// Last der letzten 7 Tage durch den Wochenschnitt der letzten 4 Wochen; `nil` ohne Vergleichswert.
        public let acuteChronicRatio: Double?

        public init(
            minutesLastSevenDays: Double,
            averageWeeklyMinutes: Double,
            loadLastSevenDays: Double,
            averageWeeklyLoad: Double,
            acuteChronicRatio: Double?
        ) {
            self.minutesLastSevenDays = minutesLastSevenDays
            self.averageWeeklyMinutes = averageWeeklyMinutes
            self.loadLastSevenDays = loadLastSevenDays
            self.averageWeeklyLoad = averageWeeklyLoad
            self.acuteChronicRatio = acuteChronicRatio
        }
    }
}

public extension AthleteStateSnapshot {
    /// Der Encoder für das Backend: snake_case-Schlüssel, ISO-8601-Daten, stabil sortiert.
    static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
