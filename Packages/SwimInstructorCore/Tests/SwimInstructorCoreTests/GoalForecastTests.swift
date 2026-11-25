import XCTest
@testable import SwimInstructorCore

/// Zielprognose aus Leistungsprofil, Startniveau und Radfahrten. Heute ist der 30.09.2026 (TestFixtures.now).
final class GoalForecastTests: XCTestCase {
    private let forecaster = GoalForecaster(calendar: TestFixtures.utc)

    private func goal(_ kind: GoalKind = .race, _ disciplines: [TrainingGoal.Discipline]) -> TrainingGoal {
        TrainingGoal(kind: kind, disciplines: disciplines, targetDate: TestFixtures.date(daysAgo: -60, hour: 8), trainingDaysPerWeek: 5, weeklyHours: 8, emphasis: [])
    }

    private func ride(daysAgo: Int, minutes: Double, kilometers: Double) -> Workout {
        let start = TestFixtures.date(daysAgo: daysAgo, hour: 8)
        return Workout(id: UUID(), sport: .bike, startDate: start, endDate: start.addingTimeInterval(minutes * 60), duration: minutes * 60, distanceMeters: kilometers * 1000)
    }

    private func level(_ sport: SportID, pace: Double? = nil, bestTimes: [StartingLevel.BestTime]? = nil) -> StartingLevel {
        StartingLevel(sport: sport, weeklyAmount: 120, longestSession: 60, status: .regular, reportedAt: TestFixtures.now, pace: pace, bestTimes: bestTimes)
    }

    private let olympic: [TrainingGoal.Discipline] = [
        .init(sport: .swim, distanceMeters: 1_500, targetDurationSeconds: 1_740),
        .init(sport: .bike, distanceMeters: 40_000, targetDurationSeconds: 4_560),
        .init(sport: .run, distanceMeters: 10_000, targetDurationSeconds: 3_300)
    ]

    func testOlympicDistanceFromProfileAndRides() throws {
        let values: [String: Double] = ["swim|css_pace_per_100m": 112, "run|threshold_pace_per_km": 330]
        let rides = [
            ride(daysAgo: 3, minutes: 60, kilometers: 30),
            ride(daysAgo: 10, minutes: 60, kilometers: 31),
            ride(daysAgo: 17, minutes: 60, kilometers: 28),
            ride(daysAgo: 5, minutes: 30, kilometers: 20), // zu kurz, zählt nicht
            ride(daysAgo: 80, minutes: 60, kilometers: 38) // zu alt
        ]
        let forecast = try XCTUnwrap(forecaster.forecast(
            goal: goal(olympic), value: { values["\($0.rawValue)|\($1.rawValue)"] }, startingLevels: [], workouts: rides, now: TestFixtures.now
        ))

        let swim = forecast.disciplines[0], bike = forecast.disciplines[1], run = forecast.disciplines[2]
        // 15 × (112 + 2 s Aufschlag für 1500 m).
        XCTAssertEqual(swim.predictedSeconds, 1_710)
        XCTAssertEqual(swim.basis, .criticalSwimSpeed(112))
        XCTAssertEqual(swim.verdict, "Zielzeit schon drin")
        // Schnitt der zwei schnellsten Fahrten 30,5 km/h, im Wettkampf 6 % schneller.
        XCTAssertEqual(bike.predictedSeconds, 4_454)
        XCTAssertEqual(bike.basis, .recentRides(30.5))
        // Riegel von einer Stunde auf Schwelle, nach dem Rad 5 % langsamer.
        XCTAssertEqual(run.predictedSeconds, 3_447)
        XCTAssertEqual(run.verdict, "Noch 2 min")
        XCTAssertEqual(forecast.transitionSeconds, 300)
        XCTAssertEqual(forecast.predictedTotal, 9_911)
        XCTAssertEqual(forecast.targetTotal, 9_900)
        XCTAssertEqual(forecast.largestGap?.sport, .run)
        XCTAssertEqual(forecast.sentence(registry: TestFixtures.triathlon), "Du bist nah an deiner Zielzeit. Mit dem Plan bis zum Zieltag ist sie gut erreichbar.")
        XCTAssertEqual(GoalForecast.clock(9_911), "2:45:11")
        XCTAssertEqual(GoalForecast.clock(1_710), "28:30")
    }

    func testASingleRunUsesTheClosestBestTimeWithoutBikeFatigue() throws {
        let target = goal(.time, [.init(sport: .run, distanceMeters: 10_000, targetDurationSeconds: 3_000)])
        let best = [StartingLevel.BestTime(distanceMeters: 5_000, seconds: 1_500)]
        let forecast = try XCTUnwrap(forecaster.forecast(
            goal: target, value: { _, _ in nil }, startingLevels: [level(.run, pace: 360, bestTimes: best)], workouts: [], now: TestFixtures.now
        ))

        XCTAssertNil(forecast.transitionSeconds)
        XCTAssertEqual(forecast.disciplines[0].predictedSeconds, 3_127)
        XCTAssertEqual(forecast.disciplines[0].basis, .bestTime(meters: 5_000, seconds: 1_500))
        XCTAssertEqual(forecast.sentence(registry: TestFixtures.triathlon), "Am meisten Zeit holst du beim Laufen.")
    }

    func testTheUsualRunPaceIsTheLastResort() throws {
        let target = goal(.time, [.init(sport: .run, distanceMeters: 10_000, targetDurationSeconds: 3_000)])
        let forecast = try XCTUnwrap(forecaster.forecast(
            goal: target, value: { _, _ in nil }, startingLevels: [level(.run, pace: 360)], workouts: [], now: TestFixtures.now
        ))

        XCTAssertEqual(forecast.disciplines[0].predictedSeconds, 3_104)
        XCTAssertEqual(forecast.disciplines[0].basis, .runPace(360))
    }

    func testMissingValuesLeaveTheDisciplineOpen() throws {
        let target = goal([
            .init(sport: .swim, distanceMeters: 1_500, targetDurationSeconds: 1_740),
            .init(sport: .bike, distanceMeters: 40_000)
        ])
        let forecast = try XCTUnwrap(forecaster.forecast(
            goal: target, value: { _, _ in nil }, startingLevels: [level(.bike, pace: 28)], workouts: [], now: TestFixtures.now
        ))

        XCTAssertNil(forecast.disciplines[0].predictedSeconds)
        XCTAssertEqual(forecast.disciplines[1].predictedSeconds, 4_852)
        XCTAssertEqual(forecast.disciplines[1].basis, .rideSpeed(28))
        XCTAssertNil(forecast.predictedTotal)
        XCTAssertNil(forecast.targetTotal)
        XCTAssertEqual(forecast.sentence(registry: TestFixtures.triathlon), "Für eine Prognose fehlen noch Leistungswerte. Trag sie im Leistungsprofil ein oder mach einen Test.")
    }

    func testAFitnessGoalHasNoForecast() {
        let fitness = goal(.fitness, [])
        XCTAssertNil(forecaster.forecast(goal: fitness, value: { _, _ in nil }, startingLevels: [], workouts: [], now: TestFixtures.now))
    }
}
