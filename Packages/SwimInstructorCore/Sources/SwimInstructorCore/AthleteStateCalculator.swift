import Foundation

/// Schwellenwerte der Berechnung. Alle Werte sind Startwerte und lassen sich später anhand
/// echter Daten justieren, ohne die Rechenlogik anzufassen.
public struct AthleteStateConfiguration: Equatable, Sendable {
    /// Eine Einheit gilt als hart, wenn sie mindestens so lang ist ...
    public var hardSessionDistanceMeters = 2000.0
    /// ... oder eine mindestens so hohe durchschnittliche Herzfrequenz hatte.
    public var hardSessionHeartRate = 150.0
    /// Ab so vielen Tagen ohne Einheit gilt es als Trainingspause.
    public var trainingPauseDays = 14
    /// Volumensprung: letzte sieben Tage mehr als dieser Faktor über dem Wochenschnitt davor.
    public var volumeSpikeFactor = 1.3
    public var elevatedRestingHeartRateBpm = 5.0
    public var hrvDropPercent = 15.0
    public var shortSleepHours = 6.0
    /// Übertrainingsrisiko: Erholung schlecht und mindestens so viele Einheiten in sieben Tagen.
    public var overreachingMinSessions = 3
    public var goalNearDays = 28
    /// So viele Tageswerte braucht die Baseline mindestens, sonst gibt es keine Abweichung.
    public var minBaselineSamples = 5

    public init() {}
}

/// Rechnet aus Rohdaten (Workouts, Tageswerte, Ziel) den `AthleteStateSnapshot`.
/// Reine Funktion ohne HealthKit-Zugriff, damit sie komplett testbar bleibt.
///
/// Zeitfenster zählen in Kalendertagen ab `now` (Tag 0 = heute):
/// - letzte sieben Tage: Tag 0 bis 6, Woche davor: Tag 7 bis 13
/// - letzte vier Wochen: Tag 0 bis 27, die vier Wochen davor: Tag 28 bis 55
/// - Erholung: aktuelle Werte Tag 0 bis 2, Baseline Tag 3 bis 30
public struct AthleteStateCalculator {
    public let configuration: AthleteStateConfiguration
    private let calendar: Calendar

    public init(
        configuration: AthleteStateConfiguration = AthleteStateConfiguration(),
        calendar: Calendar = .current
    ) {
        self.configuration = configuration
        self.calendar = calendar
    }

    public func snapshot(
        workouts: [SwimWorkout],
        vitals: [DailyVitals] = [],
        goal: AthleteGoal = .default,
        now: Date = Date()
    ) -> AthleteStateSnapshot {
        let sessions = SwimWorkoutDeduplicator.deduplicate(workouts)
            .filter { $0.startDate <= now }
            .map { DatedWorkout(workout: $0, day: dayOffset(of: $0.startDate, now: now)) }

        let lastSevenDays = sessions.filter { (0...6).contains($0.day) }
        let weekBefore = sessions.filter { (7...13).contains($0.day) }
        let threeWeeksBefore = sessions.filter { (7...27).contains($0.day) }
        let lastFourWeeks = sessions.filter { (0...27).contains($0.day) }
        let fourWeeksBefore = sessions.filter { (28...55).contains($0.day) }

        let lastSevenMeters = totalMeters(lastSevenDays)
        let weekBeforeMeters = totalMeters(weekBefore)
        let weeklyChange: Double? = weekBeforeMeters > 0
            ? roundedToTenths((lastSevenMeters - weekBeforeMeters) / weekBeforeMeters * 100)
            : nil

        let volumeSpike: Bool = {
            let baselineWeekly = totalMeters(threeWeeksBefore) / 3
            return baselineWeekly > 0 && lastSevenMeters > configuration.volumeSpikeFactor * baselineWeekly
        }()

        let recentPace = pace(of: lastFourWeeks)
        let previousPace = pace(of: fourWeeksBefore)
        var paceTrend: Double?
        if let recentPace, let previousPace {
            paceTrend = roundedToTenths(recentPace - previousPace)
        }
        let targetPace = goal.targetPaceSecondsPerHundredMeters

        let daysSinceLastWorkout = sessions.map(\.day).min()
        let daysSinceLastHard = sessions.filter { isHard($0.workout) }.map(\.day).min()

        let recovery = recoverySummary(vitals: vitals, now: now)
        let daysUntilGoal = max(0, dayDistance(from: now, to: goal.targetDate))

        var flags: [AthleteFlag] = []
        if daysSinceLastWorkout.map({ $0 >= configuration.trainingPauseDays }) ?? true {
            flags.append(.trainingPause)
        }
        if volumeSpike { flags.append(.volumeSpike) }
        if recovery.status == .poor { flags.append(.recoveryPoor) }
        if recovery.status == .poor && lastSevenDays.count >= configuration.overreachingMinSessions {
            flags.append(.overreachingRisk)
        }
        if daysUntilGoal <= configuration.goalNearDays { flags.append(.goalWithinFourWeeks) }

        return AthleteStateSnapshot(
            generatedAt: now,
            goal: .init(
                distanceMeters: goal.distanceMeters,
                targetDurationSeconds: goal.targetDurationSeconds,
                targetPaceSecondsPerHundredMeters: roundedToTenths(targetPace),
                targetDate: goal.targetDate,
                daysUntilGoal: daysUntilGoal
            ),
            volume: .init(
                lastSevenDaysMeters: lastSevenMeters,
                averageWeeklyMeters: roundedToTenths(totalMeters(lastFourWeeks) / 4),
                weeklyChangePercent: weeklyChange,
                sessionsLastSevenDays: lastSevenDays.count,
                sessionsLastFourWeeks: lastFourWeeks.count,
                longestSessionMeters: lastFourWeeks.compactMap { $0.workout.totalDistanceMeters }.max() ?? 0
            ),
            pace: .init(
                recentPaceSecondsPerHundredMeters: recentPace.map { roundedToTenths($0) },
                previousPaceSecondsPerHundredMeters: previousPace.map { roundedToTenths($0) },
                trendSecondsPerHundredMeters: paceTrend,
                gapToTargetSecondsPerHundredMeters: recentPace.map { roundedToTenths($0 - targetPace) }
            ),
            load: .init(
                daysSinceLastWorkout: daysSinceLastWorkout,
                daysSinceLastHardSession: daysSinceLastHard
            ),
            recovery: recovery,
            flags: flags
        )
    }

    // MARK: - Workouts

    private struct DatedWorkout {
        let workout: SwimWorkout
        let day: Int
    }

    private func totalMeters(_ sessions: [DatedWorkout]) -> Double {
        sessions.reduce(0) { $0 + ($1.workout.totalDistanceMeters ?? 0) }
    }

    /// Gewichtete Pace: Gesamtzeit durch Gesamtdistanz, nur über Einheiten mit Distanz.
    private func pace(of sessions: [DatedWorkout]) -> Double? {
        let measured = sessions.filter { ($0.workout.totalDistanceMeters ?? 0) > 0 }
        let meters = totalMeters(measured)
        guard meters > 0 else { return nil }
        let seconds = measured.reduce(0) { $0 + $1.workout.duration }
        return seconds / (meters / 100)
    }

    private func isHard(_ workout: SwimWorkout) -> Bool {
        (workout.totalDistanceMeters ?? 0) >= configuration.hardSessionDistanceMeters
            || (workout.averageHeartRate ?? 0) >= configuration.hardSessionHeartRate
    }

    // MARK: - Erholung

    private func recoverySummary(vitals: [DailyVitals], now: Date) -> AthleteStateSnapshot.RecoverySummary {
        let dated = vitals.map { (sample: $0, day: dayOffset(of: $0.date, now: now)) }
        let recent = dated.filter { (0...2).contains($0.day) }.map { $0.sample }
        let baseline = dated.filter { (3...30).contains($0.day) }.map { $0.sample }

        /// Mittel der aktuellen Werte und der Baseline; `nil`, wenn eins von beiden zu dünn ist.
        func averages(_ value: (DailyVitals) -> Double?) -> (recent: Double, baseline: Double)? {
            let recentValues = recent.compactMap(value)
            let baselineValues = baseline.compactMap(value)
            guard !recentValues.isEmpty, baselineValues.count >= configuration.minBaselineSamples else {
                return nil
            }
            return (mean(recentValues), mean(baselineValues))
        }

        let restingHeartRateDeviation = averages { $0.restingHeartRate }.map { $0.recent - $0.baseline }
        var hrvDeviation: Double?
        if let hrv = averages({ $0.hrvSDNN }), hrv.baseline > 0 {
            hrvDeviation = (hrv.recent - hrv.baseline) / hrv.baseline * 100
        }
        let recentSleepValues = recent.compactMap(\.sleepHours)
        let recentSleep: Double? = recentSleepValues.isEmpty ? nil : mean(recentSleepValues)

        var signals: [RecoverySignal] = []
        if let deviation = restingHeartRateDeviation, deviation >= configuration.elevatedRestingHeartRateBpm {
            signals.append(.elevatedRestingHeartRate)
        }
        if let deviation = hrvDeviation, deviation <= -configuration.hrvDropPercent {
            signals.append(.lowHeartRateVariability)
        }
        if let sleep = recentSleep, sleep < configuration.shortSleepHours {
            signals.append(.shortSleep)
        }

        let hasData = restingHeartRateDeviation != nil || hrvDeviation != nil || recentSleep != nil
        let status: RecoveryStatus
        if !hasData {
            status = .unknown
        } else if signals.isEmpty {
            status = .good
        } else if signals.count == 1 {
            status = .moderate
        } else {
            status = .poor
        }

        return .init(
            status: status,
            restingHeartRateDeviationBpm: restingHeartRateDeviation.map { roundedToTenths($0) },
            hrvDeviationPercent: hrvDeviation.map { roundedToTenths($0) },
            recentAverageSleepHours: recentSleep.map { roundedToTenths($0) },
            warningSignals: signals
        )
    }

    // MARK: - Hilfsfunktionen

    /// Kalendertage zwischen `date` und `now` (heute = 0, gestern = 1).
    private func dayOffset(of date: Date, now: Date) -> Int {
        dayDistance(from: date, to: now)
    }

    private func dayDistance(from start: Date, to end: Date) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        ).day ?? 0
    }

    private func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    /// Eine Nachkommastelle reicht für den Snapshot und hält das JSON kompakt.
    private func roundedToTenths(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
