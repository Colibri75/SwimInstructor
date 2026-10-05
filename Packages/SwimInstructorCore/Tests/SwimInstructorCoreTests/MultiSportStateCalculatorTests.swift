import XCTest
@testable import SwimInstructorCore

/// Werte von Hand nachgerechnet (siehe Kommentare). Ohne Puls ist die Last Minuten mal Faktor des Moduls:
/// Schwimmen und Laufen 1,0, Rad 0,8. Heute ist der 30.09.2026, 12:00 UTC (`TestFixtures.now`).
final class MultiSportStateCalculatorTests: XCTestCase {
    private let calculator = MultiSportStateCalculator(calendar: TestFixtures.utc)
    private let now = TestFixtures.now

    private func workout(_ sport: SportID, daysAgo: Int, minutes: Double, meters: Double?, hour: Int = 8) -> Workout {
        let start = TestFixtures.date(daysAgo: daysAgo, hour: hour)
        return Workout(
            id: UUID(), sport: sport, startDate: start, endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60, distanceMeters: meters
        )
    }

    private func goal(_ id: String) -> TrainingGoal {
        GoalTemplate.template(id: id)!.goal(targetDate: AthleteGoal.default.targetDate, trainingDaysPerWeek: 5, weeklyHours: 7)
    }

    private func extend(_ workouts: [Workout], goal: TrainingGoal) -> AthleteStateSnapshot {
        let v1 = AthleteStateCalculator(calendar: TestFixtures.utc)
            .snapshot(workouts: workouts.compactMap(SwimWorkout.init(workout:)), goal: goal.legacySwimGoal, now: now)
        return calculator.extend(v1, workouts: workouts, goal: goal, now: now)
    }

    func testMixedWeekOfAllThreeSports() throws {
        let workouts = [
            workout(.swim, daysAgo: 1, minutes: 40, meters: 2000),
            workout(.swim, daysAgo: 9, minutes: 30, meters: 1500),
            workout(.bike, daysAgo: 3, minutes: 90, meters: 42_000),
            workout(.bike, daysAgo: 20, minutes: 60, meters: 25_000),
            workout(.run, daysAgo: 0, minutes: 50, meters: 10_000, hour: 7),
            workout(.run, daysAgo: 30, minutes: 60, meters: 12_000), // älter als 4 Wochen
            workout(.run, daysAgo: -1, minutes: 30, meters: 5000) // morgen
        ]

        let snapshot = extend(workouts, goal: goal("triathlon_olympic"))
        let sports = try XCTUnwrap(snapshot.sports)

        XCTAssertEqual(snapshot.schemaVersion, 2)
        XCTAssertEqual(sports.map(\.sport), [.swim, .bike, .run])
        // Schwimmen: 7 Tage 1 × 40 min, 2000 m. 4 Wochen 70 min / 4 = 17,5 → 18; 3500 m / 4 = 875; Last 70 / 4 = 17,5.
        XCTAssertEqual(sports[0], .init(
            sport: .swim, sessionsLastSevenDays: 1, sessionsLastFourWeeks: 2,
            minutesLastSevenDays: 40, averageWeeklyMinutes: 18, metersLastSevenDays: 2000, averageWeeklyMeters: 875,
            longestSessionMeters: 2000, longestSessionMinutes: 40, loadLastSevenDays: 40, averageWeeklyLoad: 17.5,
            daysSinceLastSession: 1
        ))
        // Rad: 7 Tage 90 min, Last 90 × 0,8 = 72. 4 Wochen 150 min / 4 = 37,5 → 38; 67 km / 4 = 16 750 m; Last 120 / 4 = 30.
        XCTAssertEqual(sports[1], .init(
            sport: .bike, sessionsLastSevenDays: 1, sessionsLastFourWeeks: 2,
            minutesLastSevenDays: 90, averageWeeklyMinutes: 38, metersLastSevenDays: 42_000, averageWeeklyMeters: 16_750,
            longestSessionMeters: 42_000, longestSessionMinutes: 90, loadLastSevenDays: 72, averageWeeklyLoad: 30,
            daysSinceLastSession: 3
        ))
        // Laufen: nur heute, 50 min, 10 km; Schnitt 12,5 → 13 min, 2500 m, Last 12,5. Tag 30 und morgen zählen nicht.
        XCTAssertEqual(sports[2], .init(
            sport: .run, sessionsLastSevenDays: 1, sessionsLastFourWeeks: 1,
            minutesLastSevenDays: 50, averageWeeklyMinutes: 13, metersLastSevenDays: 10_000, averageWeeklyMeters: 2500,
            longestSessionMeters: 10_000, longestSessionMinutes: 50, loadLastSevenDays: 50, averageWeeklyLoad: 12.5,
            daysSinceLastSession: 0
        ))
        // Gesamt: 40 + 90 + 50 = 180 min, Last 40 + 72 + 50 = 162. Schnitt (70 + 150 + 50) / 4 = 67,5 → 68 min,
        // Last (70 + 120 + 50) / 4 = 60. Verhältnis 162 / 60 = 2,7.
        XCTAssertEqual(snapshot.totalLoad, .init(
            minutesLastSevenDays: 180, averageWeeklyMinutes: 68, loadLastSevenDays: 162, averageWeeklyLoad: 60, acuteChronicRatio: 2.7
        ))
    }

    func testSingleSportGoalListsOnlyRelevantSports() throws {
        var marathon = goal("run_marathon")
        let workouts = [
            workout(.run, daysAgo: 2, minutes: 45, meters: 9000),
            workout(.run, daysAgo: 12, minutes: 90, meters: 18_000)
        ]

        let onlyRun = extend(workouts, goal: marathon)
        XCTAssertEqual(onlyRun.sports?.map(\.sport), [.run])
        // 7 Tage 45, Schnitt (45 + 90) / 4 = 33,75; Verhältnis 45 / 33,75 = 1,333 → 1,33.
        XCTAssertEqual(onlyRun.totalLoad?.acuteChronicRatio, 1.33)
        XCTAssertEqual(onlyRun.totalLoad?.averageWeeklyLoad, 33.8)

        // Schwimmen mit Schwerpunkt, aber ohne Einheit: steht mit Nullen und ohne "zuletzt" drin.
        marathon = marathon.settingEmphasis(20, for: .swim)
        let withSwim = try XCTUnwrap(extend(workouts, goal: marathon).sports)
        XCTAssertEqual(withSwim.map(\.sport), [.swim, .run])
        XCTAssertEqual(withSwim[0].sessionsLastFourWeeks, 0)
        XCTAssertEqual(withSwim[0].longestSessionMeters, 0)
        XCTAssertNil(withSwim[0].daysSinceLastSession)
    }

    func testGoalPartAndNoHistory() throws {
        let olympic = goal("triathlon_olympic")
        let snapshot = extend([], goal: olympic)

        let goalPart = try XCTUnwrap(snapshot.trainingGoal)
        XCTAssertEqual(goalPart.template, "triathlon_olympic")
        XCTAssertEqual(goalPart.daysUntilGoal, snapshot.goal.daysUntilGoal)
        XCTAssertEqual(goalPart.daysUntilGoal, 277)
        XCTAssertEqual(goalPart.disciplines, olympic.disciplines)
        XCTAssertEqual(goalPart.emphasis, olympic.emphasis)
        XCTAssertEqual(goalPart.trainingDaysPerWeek, 5)
        XCTAssertEqual(goalPart.weeklyHours, 7)
        // Ohne Training: alle Sportarten des Ziels mit Nullen, kein Verhältnis.
        XCTAssertEqual(snapshot.sports?.map(\.sport), [.swim, .bike, .run])
        XCTAssertEqual(snapshot.totalLoad, .init(minutesLastSevenDays: 0, averageWeeklyMinutes: 0, loadLastSevenDays: 0, averageWeeklyLoad: 0, acuteChronicRatio: nil))
        // Der v1-Teil bleibt, wie der Rechner ihn erzeugt hat.
        XCTAssertEqual(snapshot.version1, AthleteStateCalculator(calendar: TestFixtures.utc).snapshot(workouts: [], goal: olympic.legacySwimGoal, now: now))
    }

    func testDuplicatesUnknownSportsAndHeartRate() throws {
        let ride = workout(.bike, daysAgo: 1, minutes: 60, meters: 30_000)
        let duplicate = Workout(id: UUID(), sport: .bike, startDate: ride.startDate, endDate: ride.endDate, duration: ride.duration)
        let kayak = workout("kayak", daysAgo: 1, minutes: 60, meters: 8000)
        let withPulse = MultiSportStateCalculator(
            calendar: TestFixtures.utc,
            loadCalculator: TrainingLoadCalculator(restingHeartRate: 50, maximumHeartRate: 190)
        )
        let pulsed = Workout(
            id: UUID(), sport: .run, startDate: TestFixtures.date(daysAgo: 2, hour: 8),
            endDate: TestFixtures.date(daysAgo: 2, hour: 9), duration: 3600, distanceMeters: 10_000, averageHeartRate: 120
        )
        let olympic = goal("triathlon_olympic")
        let v1 = AthleteStateCalculator(calendar: TestFixtures.utc).snapshot(workouts: [], goal: olympic.legacySwimGoal, now: now)

        let snapshot = withPulse.extend(v1, workouts: [ride, duplicate, kayak, pulsed], goal: olympic, now: now)
        let sports = try XCTUnwrap(snapshot.sports)

        XCTAssertEqual(sports.map(\.sport), [.swim, .bike, .run], "Unbekannte Sportart geht nicht zum Server")
        XCTAssertEqual(sports[1].sessionsLastSevenDays, 1, "Duplikat zählt einmal")
        // Session-RPE aus dem Puls: Reserve (120 - 50) / 140 = 0,5 → Anstrengung 3 → 60 × 3 / 4 = 45.
        XCTAssertEqual(sports[2].loadLastSevenDays, 45)
    }
}
