import XCTest
@testable import SwimInstructorCore

/// Alle Szenarien laufen mit festem "jetzt" (30.09.2026, 12:00 UTC) und UTC-Kalender, damit die
/// Erwartungswerte von Hand nachgerechnet werden können. `daysAgo` zählt Kalendertage (heute = 0).
final class AthleteStateCalculatorTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!
    private lazy var calculator = AthleteStateCalculator(calendar: calendar)

    // MARK: - Helfer

    private func day(_ daysAgo: Int, hour: Int) -> Date {
        let midnight = calendar.startOfDay(for: now)
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: midnight)!
        return date.addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func workout(
        daysAgo: Int,
        meters: Double?,
        seconds: TimeInterval,
        heartRate: Double? = nil,
        hour: Int = 10
    ) -> SwimWorkout {
        let start = day(daysAgo, hour: hour)
        return SwimWorkout(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(seconds),
            duration: seconds,
            totalDistanceMeters: meters,
            lapCount: nil,
            totalStrokeCount: nil,
            averageHeartRate: heartRate
        )
    }

    /// Baseline für Tag 3 bis 30 (28 Tage) plus die drei aktuellen Tage 0 bis 2.
    private func vitals(
        baselineRestingHeartRate: Double,
        baselineHRV: Double,
        recentRestingHeartRate: [Double],
        recentHRV: [Double],
        recentSleep: [Double]
    ) -> [DailyVitals] {
        var result: [DailyVitals] = (3...30).map { daysAgo in
            DailyVitals(
                date: day(daysAgo, hour: 8),
                restingHeartRate: baselineRestingHeartRate,
                hrvSDNN: baselineHRV
            )
        }
        for offset in 0..<3 {
            result.append(
                DailyVitals(
                    date: day(offset, hour: 8),
                    restingHeartRate: recentRestingHeartRate[offset],
                    hrvSDNN: recentHRV[offset],
                    sleepHours: recentSleep[offset]
                )
            )
        }
        return result
    }

    // MARK: - Szenario 1: Anfänger / niedriges Volumen

    func testScenarioBeginnerWithLowVolume() {
        let workouts = [
            workout(daysAgo: 2, meters: 400, seconds: 1080),
            workout(daysAgo: 9, meters: 500, seconds: 1200),
            workout(daysAgo: 16, meters: 500, seconds: 1320)
        ]

        let snapshot = calculator.snapshot(workouts: workouts, now: now)

        XCTAssertEqual(snapshot.goal.daysUntilGoal, 277)
        XCTAssertEqual(snapshot.goal.targetPaceSecondsPerHundredMeters, 94.7, accuracy: 0.05)

        XCTAssertEqual(snapshot.volume.lastSevenDaysMeters, 400)
        XCTAssertEqual(snapshot.volume.averageWeeklyMeters, 350.0, accuracy: 0.05)
        // Woche davor 500 m, jetzt 400 m: (400 - 500) / 500 = -20 %
        XCTAssertEqual(snapshot.volume.weeklyChangePercent ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.volume.sessionsLastSevenDays, 1)
        XCTAssertEqual(snapshot.volume.sessionsLastFourWeeks, 3)
        XCTAssertEqual(snapshot.volume.longestSessionMeters, 500)

        // 3600 s / (1400 m / 100) = 257,14 s/100 m; Lücke zum Ziel 257,14 - 94,74 = 162,4
        XCTAssertEqual(snapshot.pace.recentPaceSecondsPerHundredMeters ?? .nan, 257.1, accuracy: 0.05)
        XCTAssertNil(snapshot.pace.previousPaceSecondsPerHundredMeters)
        XCTAssertNil(snapshot.pace.trendSecondsPerHundredMeters)
        XCTAssertEqual(snapshot.pace.gapToTargetSecondsPerHundredMeters ?? .nan, 162.4, accuracy: 0.05)

        XCTAssertEqual(snapshot.load.daysSinceLastWorkout, 2)
        XCTAssertNil(snapshot.load.daysSinceLastHardSession)
        XCTAssertEqual(snapshot.recovery.status, .unknown)
        XCTAssertEqual(snapshot.flags, [])
    }

    // MARK: - Szenario 2: guter Fortschritt

    private func goodProgressWorkouts() -> [SwimWorkout] {
        let recent: [(Int, Double)] = [
            (1, 2000), (4, 1500), (8, 1800), (11, 1500),
            (15, 1800), (18, 1500), (22, 1800), (25, 1500)
        ]
        let previous: [Int] = [30, 37, 44, 51]
        // Aktuell 120 s/100 m (1,2 s pro Meter), davor 160 s/100 m (1,6 s pro Meter).
        return recent.map { workout(daysAgo: $0.0, meters: $0.1, seconds: $0.1 * 1.2) }
            + previous.map { workout(daysAgo: $0, meters: 1500, seconds: 2400) }
    }

    func testScenarioGoodProgress() {
        let healthy = vitals(
            baselineRestingHeartRate: 50,
            baselineHRV: 60,
            recentRestingHeartRate: [51, 50, 49],
            recentHRV: [60, 62, 58],
            recentSleep: [7.5, 8, 7]
        )

        let snapshot = calculator.snapshot(workouts: goodProgressWorkouts(), vitals: healthy, now: now)

        XCTAssertEqual(snapshot.volume.lastSevenDaysMeters, 3500)
        XCTAssertEqual(snapshot.volume.averageWeeklyMeters, 3350.0, accuracy: 0.05) // 13400 / 4
        // Woche davor 3300 m: (3500 - 3300) / 3300 = 6,06 %
        XCTAssertEqual(snapshot.volume.weeklyChangePercent ?? .nan, 6.1, accuracy: 0.05)
        XCTAssertEqual(snapshot.volume.sessionsLastSevenDays, 2)
        XCTAssertEqual(snapshot.volume.sessionsLastFourWeeks, 8)
        XCTAssertEqual(snapshot.volume.longestSessionMeters, 2000)

        XCTAssertEqual(snapshot.pace.recentPaceSecondsPerHundredMeters ?? .nan, 120.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.pace.previousPaceSecondsPerHundredMeters ?? .nan, 160.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.pace.trendSecondsPerHundredMeters ?? .nan, -40.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.pace.gapToTargetSecondsPerHundredMeters ?? .nan, 25.3, accuracy: 0.05)

        XCTAssertEqual(snapshot.load.daysSinceLastWorkout, 1)
        XCTAssertEqual(snapshot.load.daysSinceLastHardSession, 1) // 2000 m gilt als hart

        XCTAssertEqual(snapshot.recovery.status, .good)
        XCTAssertEqual(snapshot.recovery.restingHeartRateDeviationBpm ?? .nan, 0.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.recovery.hrvDeviationPercent ?? .nan, 0.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.recovery.recentAverageSleepHours ?? .nan, 7.5, accuracy: 0.05)
        XCTAssertEqual(snapshot.recovery.warningSignals, [])
        XCTAssertEqual(snapshot.flags, [])
    }

    // MARK: - Szenario 3: Trainingspause / Verletzung

    func testScenarioTrainingPause() {
        let workouts = [
            workout(daysAgo: 20, meters: 1500, seconds: 1800),
            workout(daysAgo: 27, meters: 1500, seconds: 1800),
            workout(daysAgo: 34, meters: 1500, seconds: 1800)
        ]

        let snapshot = calculator.snapshot(workouts: workouts, now: now)

        XCTAssertEqual(snapshot.volume.lastSevenDaysMeters, 0)
        XCTAssertEqual(snapshot.volume.averageWeeklyMeters, 750.0, accuracy: 0.05) // 3000 / 4
        XCTAssertNil(snapshot.volume.weeklyChangePercent) // Woche davor ebenfalls 0 m
        XCTAssertEqual(snapshot.volume.sessionsLastSevenDays, 0)
        XCTAssertEqual(snapshot.volume.sessionsLastFourWeeks, 2)

        XCTAssertEqual(snapshot.pace.recentPaceSecondsPerHundredMeters ?? .nan, 120.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.pace.previousPaceSecondsPerHundredMeters ?? .nan, 120.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.pace.trendSecondsPerHundredMeters ?? .nan, 0.0, accuracy: 0.05)

        XCTAssertEqual(snapshot.load.daysSinceLastWorkout, 20)
        XCTAssertNil(snapshot.load.daysSinceLastHardSession)
        XCTAssertEqual(snapshot.flags, [.trainingPause])
    }

    // MARK: - Szenario 4: kurz vor dem Zieldatum

    func testScenarioShortlyBeforeGoalDate() {
        let sessions: [(Int, Double)] = [
            (2, 3000), (5, 2000), (9, 3000), (13, 2000),
            (16, 2000), (17, 3000), (23, 3000), (24, 2000)
        ]
        // Konstant 110 s/100 m (1,1 s pro Meter).
        let workouts = sessions.map { workout(daysAgo: $0.0, meters: $0.1, seconds: $0.1 * 1.1) }
        let goal = AthleteGoal(
            distanceMeters: 3800,
            targetDurationSeconds: 3600,
            targetDate: calendar.date(from: DateComponents(year: 2026, month: 10, day: 14))!
        )

        let snapshot = calculator.snapshot(workouts: workouts, goal: goal, now: now)

        XCTAssertEqual(snapshot.goal.daysUntilGoal, 14)
        XCTAssertEqual(snapshot.volume.lastSevenDaysMeters, 5000)
        XCTAssertEqual(snapshot.volume.averageWeeklyMeters, 5000.0, accuracy: 0.05) // 20000 / 4
        XCTAssertEqual(snapshot.volume.weeklyChangePercent ?? .nan, 0.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.volume.sessionsLastSevenDays, 2)
        XCTAssertEqual(snapshot.volume.sessionsLastFourWeeks, 8)
        XCTAssertEqual(snapshot.volume.longestSessionMeters, 3000)

        XCTAssertEqual(snapshot.pace.recentPaceSecondsPerHundredMeters ?? .nan, 110.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.pace.gapToTargetSecondsPerHundredMeters ?? .nan, 15.3, accuracy: 0.05)
        XCTAssertEqual(snapshot.load.daysSinceLastHardSession, 2)
        // 5000 m liegen unter 1,3 x 5000 m Wochenschnitt: kein Volumensprung, nur die Zielnähe.
        XCTAssertEqual(snapshot.flags, [.goalWithinFourWeeks])
    }

    // MARK: - Szenario 5: Übertraining-Warnsignal

    func testScenarioOvertrainingWarning() {
        let hard: [(Int, Double)] = [(0, 155), (1, 158), (3, 156), (4, 155)]
        let workouts = hard.map { workout(daysAgo: $0.0, meters: 2500, seconds: 3000, heartRate: $0.1) }
            + [8, 11, 15, 18, 22, 25].map { workout(daysAgo: $0, meters: 1500, seconds: 1800) }
        let strained = vitals(
            baselineRestingHeartRate: 50,
            baselineHRV: 60,
            recentRestingHeartRate: [56, 57, 58],
            recentHRV: [48, 50, 46],
            recentSleep: [5.5, 6.0, 5.0]
        )

        let snapshot = calculator.snapshot(workouts: workouts, vitals: strained, now: now)

        XCTAssertEqual(snapshot.volume.lastSevenDaysMeters, 10000)
        XCTAssertEqual(snapshot.volume.averageWeeklyMeters, 4750.0, accuracy: 0.05) // 19000 / 4
        // Woche davor 3000 m: (10000 - 3000) / 3000 = 233,3 %
        XCTAssertEqual(snapshot.volume.weeklyChangePercent ?? .nan, 233.3, accuracy: 0.05)
        XCTAssertEqual(snapshot.volume.sessionsLastSevenDays, 4)
        XCTAssertEqual(snapshot.volume.sessionsLastFourWeeks, 10)

        XCTAssertEqual(snapshot.load.daysSinceLastWorkout, 0)
        XCTAssertEqual(snapshot.load.daysSinceLastHardSession, 0)

        // Ruhepuls 57 statt 50 (+7), HRV 48 statt 60 (-20 %), Schlaf 5,5 h: alle drei Signale.
        XCTAssertEqual(snapshot.recovery.status, .poor)
        XCTAssertEqual(snapshot.recovery.restingHeartRateDeviationBpm ?? .nan, 7.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.recovery.hrvDeviationPercent ?? .nan, -20.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.recovery.recentAverageSleepHours ?? .nan, 5.5, accuracy: 0.05)
        XCTAssertEqual(
            snapshot.recovery.warningSignals,
            [.elevatedRestingHeartRate, .lowHeartRateVariability, .shortSleep]
        )
        XCTAssertEqual(snapshot.flags, [.volumeSpike, .recoveryPoor, .overreachingRisk])
    }

    // MARK: - Randfälle

    func testNoWorkoutsAtAllIsATrainingPauseWithoutNumbers() {
        let snapshot = calculator.snapshot(workouts: [], now: now)

        XCTAssertNil(snapshot.load.daysSinceLastWorkout)
        XCTAssertNil(snapshot.pace.recentPaceSecondsPerHundredMeters)
        XCTAssertNil(snapshot.pace.gapToTargetSecondsPerHundredMeters)
        XCTAssertEqual(snapshot.volume.lastSevenDaysMeters, 0)
        XCTAssertEqual(snapshot.volume.longestSessionMeters, 0)
        XCTAssertEqual(snapshot.flags, [.trainingPause])
    }

    func testWorkoutWithoutDistanceCountsAsSessionButNotForVolumeOrPace() {
        let workouts = [
            workout(daysAgo: 1, meters: nil, seconds: 3690),
            workout(daysAgo: 3, meters: 1000, seconds: 1500)
        ]

        let snapshot = calculator.snapshot(workouts: workouts, now: now)

        XCTAssertEqual(snapshot.volume.sessionsLastSevenDays, 2)
        XCTAssertEqual(snapshot.volume.lastSevenDaysMeters, 1000)
        XCTAssertEqual(snapshot.pace.recentPaceSecondsPerHundredMeters ?? .nan, 150.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.load.daysSinceLastWorkout, 1)
    }

    func testHighAverageHeartRateMakesShortSessionHard() {
        let workouts = [workout(daysAgo: 2, meters: 800, seconds: 1200, heartRate: 160)]

        let snapshot = calculator.snapshot(workouts: workouts, now: now)

        XCTAssertEqual(snapshot.load.daysSinceLastHardSession, 2)
    }

    func testDuplicateWorkoutsFromTwoSourcesCountOnce() {
        // Dieselbe Einheit, einmal mit und einmal ohne Distanz (zweite Quelle).
        let workouts = [
            workout(daysAgo: 1, meters: nil, seconds: 3600, hour: 10),
            workout(daysAgo: 1, meters: 2400, seconds: 3600, hour: 10)
        ]

        let snapshot = calculator.snapshot(workouts: workouts, now: now)

        XCTAssertEqual(snapshot.volume.sessionsLastSevenDays, 1)
        XCTAssertEqual(snapshot.volume.lastSevenDaysMeters, 2400)
    }

    func testWorkoutsInTheFutureAreIgnored() {
        let workouts = [workout(daysAgo: -2, meters: 1000, seconds: 1800)]

        let snapshot = calculator.snapshot(workouts: workouts, now: now)

        XCTAssertEqual(snapshot.volume.sessionsLastFourWeeks, 0)
        XCTAssertEqual(snapshot.flags, [.trainingPause])
    }

    func testGoalDateInThePastYieldsZeroDays() {
        let goal = AthleteGoal(
            distanceMeters: 3800,
            targetDurationSeconds: 3600,
            targetDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        )

        let snapshot = calculator.snapshot(workouts: [], goal: goal, now: now)

        XCTAssertEqual(snapshot.goal.daysUntilGoal, 0)
        XCTAssertTrue(snapshot.flags.contains(.goalWithinFourWeeks))
    }

    func testVitalsWithTooFewBaselineSamplesAreIgnored() {
        // Nur 3 Baseline-Tage (Minimum ist 5): keine Ruhepuls-/HRV-Abweichung, Schlaf zählt aber.
        var sparse: [DailyVitals] = (3...5).map {
            DailyVitals(date: day($0, hour: 8), restingHeartRate: 50, hrvSDNN: 60)
        }
        sparse.append(DailyVitals(date: day(0, hour: 8), restingHeartRate: 60, hrvSDNN: 30, sleepHours: 8))

        let snapshot = calculator.snapshot(workouts: [], vitals: sparse, now: now)

        XCTAssertNil(snapshot.recovery.restingHeartRateDeviationBpm)
        XCTAssertNil(snapshot.recovery.hrvDeviationPercent)
        XCTAssertEqual(snapshot.recovery.recentAverageSleepHours ?? .nan, 8.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.recovery.status, .good)
    }

    func testSingleWarningSignalIsModerate() {
        let vitalsWithShortSleepOnly = vitals(
            baselineRestingHeartRate: 50,
            baselineHRV: 60,
            recentRestingHeartRate: [50, 50, 50],
            recentHRV: [60, 60, 60],
            recentSleep: [5, 5.5, 5]
        )

        let snapshot = calculator.snapshot(workouts: [], vitals: vitalsWithShortSleepOnly, now: now)

        XCTAssertEqual(snapshot.recovery.status, .moderate)
        XCTAssertEqual(snapshot.recovery.warningSignals, [.shortSleep])
        XCTAssertFalse(snapshot.flags.contains(.recoveryPoor))
    }

    func testDefaultGoalIsThreePointEightKilometersUnderAnHour() {
        let goal = AthleteGoal.default

        XCTAssertEqual(goal.distanceMeters, 3800)
        XCTAssertEqual(goal.targetDurationSeconds, 3600)
        XCTAssertEqual(goal.targetPaceSecondsPerHundredMeters, 94.7368, accuracy: 0.001)
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let components = berlin.dateComponents([.year, .month, .day], from: goal.targetDate)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 4)
    }

    // MARK: - JSON-Schema

    func testSnapshotJSONSchemaKeysAreStable() throws {
        let healthy = vitals(
            baselineRestingHeartRate: 50,
            baselineHRV: 60,
            recentRestingHeartRate: [51, 50, 49],
            recentHRV: [60, 62, 58],
            recentSleep: [7.5, 8, 7]
        )
        let snapshot = calculator.snapshot(workouts: goodProgressWorkouts(), vitals: healthy, now: now)

        let data = try AthleteStateSnapshot.jsonEncoder().encode(snapshot)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(
            Set(root.keys),
            ["schema_version", "generated_at", "goal", "volume", "pace", "load", "recovery", "flags"]
        )
        XCTAssertEqual(root["schema_version"] as? Int, AthleteStateSnapshot.currentSchemaVersion)
        XCTAssertEqual(
            Set(try XCTUnwrap(root["goal"] as? [String: Any]).keys),
            [
                "distance_meters", "target_duration_seconds", "target_pace_seconds_per_hundred_meters",
                "target_date", "days_until_goal"
            ]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(root["volume"] as? [String: Any]).keys),
            [
                "last_seven_days_meters", "average_weekly_meters", "weekly_change_percent",
                "sessions_last_seven_days", "sessions_last_four_weeks", "longest_session_meters"
            ]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(root["pace"] as? [String: Any]).keys),
            [
                "recent_pace_seconds_per_hundred_meters", "previous_pace_seconds_per_hundred_meters",
                "trend_seconds_per_hundred_meters", "gap_to_target_seconds_per_hundred_meters"
            ]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(root["load"] as? [String: Any]).keys),
            ["days_since_last_workout", "days_since_last_hard_session"]
        )
        XCTAssertEqual(
            Set(try XCTUnwrap(root["recovery"] as? [String: Any]).keys),
            [
                "status", "resting_heart_rate_deviation_bpm", "hrv_deviation_percent",
                "recent_average_sleep_hours", "warning_signals"
            ]
        )
    }

    func testFlagAndStatusRawValuesAreStable() throws {
        XCTAssertEqual(AthleteFlag.trainingPause.rawValue, "training_pause")
        XCTAssertEqual(AthleteFlag.volumeSpike.rawValue, "volume_spike")
        XCTAssertEqual(AthleteFlag.recoveryPoor.rawValue, "recovery_poor")
        XCTAssertEqual(AthleteFlag.overreachingRisk.rawValue, "overreaching_risk")
        XCTAssertEqual(AthleteFlag.goalWithinFourWeeks.rawValue, "goal_within_four_weeks")
        XCTAssertEqual(RecoveryStatus.unknown.rawValue, "unknown")
        XCTAssertEqual(RecoverySignal.shortSleep.rawValue, "short_sleep")

        let snapshot = calculator.snapshot(workouts: [], now: now)
        let json = try XCTUnwrap(
            String(data: AthleteStateSnapshot.jsonEncoder().encode(snapshot), encoding: .utf8)
        )
        XCTAssertTrue(json.contains("\"training_pause\""))
    }

    func testSnapshotSurvivesJSONRoundTrip() throws {
        let snapshot = calculator.snapshot(workouts: goodProgressWorkouts(), now: now)

        let data = try AthleteStateSnapshot.jsonEncoder().encode(snapshot)
        let decoded = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }
}
