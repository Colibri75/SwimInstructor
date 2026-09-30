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
public struct AthleteStateSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let goal: GoalSummary
    public let volume: VolumeSummary
    public let pace: PaceSummary
    public let load: LoadSummary
    public let recovery: RecoverySummary
    public let flags: [AthleteFlag]

    public init(
        schemaVersion: Int = AthleteStateSnapshot.currentSchemaVersion,
        generatedAt: Date,
        goal: GoalSummary,
        volume: VolumeSummary,
        pace: PaceSummary,
        load: LoadSummary,
        recovery: RecoverySummary,
        flags: [AthleteFlag]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.goal = goal
        self.volume = volume
        self.pace = pace
        self.load = load
        self.recovery = recovery
        self.flags = flags
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
