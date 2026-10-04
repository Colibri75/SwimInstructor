import XCTest
@testable import SwimInstructorCore

final class SnapshotBuilderTests: XCTestCase {
    func testReadsWindowsTheCalculatorNeeds() async throws {
        let workouts = FakeWorkoutRepository(workouts: [TestFixtures.workout(daysAgo: 2, meters: 1000)])
        let vitals = FakeVitalsRepository()
        let builder = SnapshotBuilder(workoutRepository: workouts, vitalsRepository: vitals, calendar: TestFixtures.utc)

        _ = try await builder.build(now: TestFixtures.now)

        // Tag 0 bis 55 für Workouts und Tageswerte (Statistik bis 8 Wochen), jeweils ab Mitternacht.
        XCTAssertEqual(workouts.requestedStart, TestFixtures.date(daysAgo: 55, hour: 0))
        XCTAssertEqual(vitals.requestedStart, TestFixtures.date(daysAgo: 55, hour: 0))
    }

    func testSnapshotMatchesCalculatorAndWorkoutsAreCleaned() async throws {
        let recent = TestFixtures.workout(daysAgo: 1, meters: 1500)
        // Dieselbe Einheit aus einer zweiten Quelle, ohne Distanz: fällt als Duplikat weg.
        let duplicate = SwimWorkout(
            id: UUID(), startDate: recent.startDate, endDate: recent.endDate, duration: recent.duration,
            totalDistanceMeters: nil, lapCount: nil, totalStrokeCount: nil, averageHeartRate: nil
        )
        let older = TestFixtures.workout(daysAgo: 5, meters: 1000)
        let vitals = (0...10).map { DailyVitals(date: TestFixtures.date(daysAgo: $0, hour: 8), restingHeartRate: 55) }
        let builder = SnapshotBuilder(
            workoutRepository: FakeWorkoutRepository(workouts: [older, duplicate, recent]),
            vitalsRepository: FakeVitalsRepository(vitals: vitals),
            calendar: TestFixtures.utc
        )

        let reading = try await builder.build(now: TestFixtures.now)

        let expected = AthleteStateCalculator(calendar: TestFixtures.utc)
            .snapshot(workouts: [older, duplicate, recent], vitals: vitals, now: TestFixtures.now)
        XCTAssertEqual(reading.snapshot, expected)
        XCTAssertEqual(reading.snapshot.volume.lastSevenDaysMeters, 2500)
        XCTAssertEqual(reading.workouts.map(\.id), [recent.id, older.id])
        XCTAssertTrue(reading.vitalsAvailable)
        XCTAssertEqual(reading.vitals, vitals, "Für die Statistik")
    }

    func testMissingVitalsStillProduceSnapshot() async throws {
        let builder = SnapshotBuilder(
            workoutRepository: FakeWorkoutRepository(workouts: [TestFixtures.workout(daysAgo: 1, meters: 1500)]),
            vitalsRepository: FakeVitalsRepository(error: TestError(message: "kein Zugriff")),
            calendar: TestFixtures.utc
        )

        let reading = try await builder.build(now: TestFixtures.now)

        XCTAssertFalse(reading.vitalsAvailable)
        XCTAssertEqual(reading.vitals, [])
        XCTAssertEqual(reading.snapshot.recovery.status, .unknown)
    }

    // MARK: - Alle Sportarten (T1)

    func testAllSportsReadingKeepsSwimSnapshotUnchanged() async throws {
        let swimRecent = TestFixtures.workout(daysAgo: 1, meters: 1500)
        let swimOlder = TestFixtures.workout(daysAgo: 5, meters: 1000)
        let ride = Workout(
            id: UUID(), sport: .bike, startDate: TestFixtures.date(daysAgo: 2, hour: 9),
            endDate: TestFixtures.date(daysAgo: 2, hour: 11), duration: 7200, distanceMeters: 55_000
        )
        let run = Workout(
            id: UUID(), sport: .run, startDate: TestFixtures.date(daysAgo: 0, hour: 7),
            endDate: TestFixtures.date(daysAgo: 0, hour: 8), duration: 3600, distanceMeters: 10_000
        )
        // Dieselbe Fahrt aus einer zweiten Quelle, ohne Strecke: fällt weg.
        let rideDuplicate = Workout(
            id: UUID(), sport: .bike, startDate: ride.startDate, endDate: ride.endDate, duration: 7200
        )
        let vitals = (0...10).map { DailyVitals(date: TestFixtures.date(daysAgo: $0, hour: 8), restingHeartRate: 55) }
        let repository = FakeAllSportsRepository(
            workouts: [Workout(swim: swimOlder), ride, rideDuplicate, Workout(swim: swimRecent), run]
        )
        let builder = SnapshotBuilder(
            repository: repository,
            vitalsRepository: FakeVitalsRepository(vitals: vitals),
            goalProvider: { .default },
            calendar: TestFixtures.utc
        )

        let reading = try await builder.build(now: TestFixtures.now)

        // Der Schwimm-Snapshot sieht Rad und Laufen nicht: genau wie vorher nur aus den Schwimmeinheiten.
        let swimOnly = try await SnapshotBuilder(
            workoutRepository: FakeWorkoutRepository(workouts: [swimOlder, swimRecent]),
            vitalsRepository: FakeVitalsRepository(vitals: vitals),
            calendar: TestFixtures.utc
        ).build(now: TestFixtures.now)
        XCTAssertEqual(reading.snapshot, swimOnly.snapshot)
        XCTAssertEqual(reading.workouts, swimOnly.workouts)
        XCTAssertEqual(reading.allWorkouts.map(\.id), [run.id, swimRecent.id, ride.id, swimOlder.id])
        XCTAssertEqual(repository.requestedStart, TestFixtures.date(daysAgo: 55, hour: 0))
    }

    func testTrainingGoalMakesASnapshotV2() async throws {
        let swim = TestFixtures.workout(daysAgo: 1, meters: 1500)
        let run = Workout(
            id: UUID(), sport: .run, startDate: TestFixtures.date(daysAgo: 2, hour: 7),
            endDate: TestFixtures.date(daysAgo: 2, hour: 8), duration: 3600, distanceMeters: 10_000
        )
        let goal = GoalTemplate.template(id: "triathlon_olympic")!
            .goal(targetDate: AthleteGoal.default.targetDate, trainingDaysPerWeek: 5, weeklyHours: 7)
        var reads = 0
        let builder = SnapshotBuilder(
            repository: FakeAllSportsRepository(workouts: [Workout(swim: swim), run]),
            vitalsRepository: FakeVitalsRepository(),
            trainingGoalProvider: {
                reads += 1
                return goal
            },
            calendar: TestFixtures.utc
        )

        let reading = try await builder.build(now: TestFixtures.now)

        XCTAssertEqual(reads, 1, "Ziel einmal pro Durchlauf lesen")
        XCTAssertEqual(reading.snapshot.schemaVersion, 2)
        XCTAssertEqual(reading.snapshot.trainingGoal?.template, "triathlon_olympic")
        XCTAssertEqual(reading.snapshot.sports?.map(\.sport), [.swim, .bike, .run])
        XCTAssertEqual(reading.snapshot.sports?.last?.metersLastSevenDays, 10_000)
        // v1-Teil: genau der bisherige Snapshot für den Schwimmteil des Ziels.
        let swimOnly = try await SnapshotBuilder(
            workoutRepository: FakeWorkoutRepository(workouts: [swim]),
            vitalsRepository: FakeVitalsRepository(),
            goal: goal.legacySwimGoal,
            calendar: TestFixtures.utc
        ).build(now: TestFixtures.now)
        XCTAssertEqual(reading.snapshot.version1, swimOnly.snapshot)
        XCTAssertEqual(reading.snapshot.goal.distanceMeters, 1500)
    }

    // MARK: - Leistungsprofil (T2b)

    private func profileBuilder(
        performance: FakePerformanceRepository?, workouts: [Workout], vitals: [DailyVitals] = [], profile: PerformanceProfile = .empty
    ) -> SnapshotBuilder {
        let goal = GoalTemplate.template(id: "triathlon_olympic")!
            .goal(targetDate: AthleteGoal.default.targetDate, trainingDaysPerWeek: 5, weeklyHours: 7)
        return SnapshotBuilder(
            repository: FakeAllSportsRepository(workouts: workouts),
            vitalsRepository: FakeVitalsRepository(vitals: vitals),
            trainingGoalProvider: { goal },
            performanceRepository: performance,
            profileProvider: { profile },
            calendar: TestFixtures.utc
        )
    }

    func testPerformanceProfileGoesIntoTheSnapshotAndLoadUsesHeartRate() async throws {
        let ride = TestFixtures.workout(.bike, daysAgo: 2, minutes: 60, meters: 30_000, heartRate: 150)
        let repository = FakePerformanceRepository(maximumHeartRate: 190, age: 40)
        let profile = PerformanceProfile(values: [TestFixtures.performance(.criticalSwimPace, 105, .tested, sport: .swim, daysAgo: 5)])
        let vitals = [DailyVitals(date: TestFixtures.date(daysAgo: 0, hour: 0), restingHeartRate: 50)]

        let reading = try await profileBuilder(performance: repository, workouts: [ride], vitals: vitals, profile: profile)
            .build(now: TestFixtures.now)

        XCTAssertEqual(repository.requestedStart, TestFixtures.utc.date(byAdding: .day, value: -182, to: TestFixtures.now))
        let performance = try XCTUnwrap(reading.snapshot.performance)
        XCTAssertEqual(performance.athlete.map(\.value), [190, 50])
        XCTAssertEqual(performance.sports.map(\.sport), [.swim, .bike, .run])
        XCTAssertEqual(performance.sports.first?.values.first?.source, .tested)
        XCTAssertEqual(performance.sports[1].values.first?.value, 162, "85 % von 190")
        // TRIMP mit Ruhepuls 50 und Maximalpuls 190: 60 min, Reserve 100/140, mal 0,8 für Rad.
        let reserve = 100.0 / 140
        let trimp = 60 * reserve * 0.64 * exp(1.92 * reserve) * 0.8
        XCTAssertEqual(reading.snapshot.sports?[1].loadLastSevenDays ?? 0, (trimp * 10).rounded() / 10, accuracy: 0.001)
        XCTAssertEqual(reading.snapshot.version1.performance, nil)
    }

    func testWithoutHeartRateFromHealthTheProfileUsesConfirmedValuesAndFormulas() async throws {
        let repository = FakePerformanceRepository(age: 40, error: TestError(message: "kein Puls"))
        let reading = try await profileBuilder(performance: repository, workouts: []).build(now: TestFixtures.now)

        let performance = try XCTUnwrap(reading.snapshot.performance)
        XCTAssertEqual(performance.athlete, [.init(metric: .maxHeartRate, value: 180, source: .formula, measuredAt: TestFixtures.now)])
        XCTAssertEqual(performance.sports.map(\.sport), [.swim, .bike, .run], "Pulszonen aus der Faustformel")
    }

    func testWithoutPerformanceRepositoryTheSnapshotHasNoProfile() async throws {
        let ride = TestFixtures.workout(.bike, daysAgo: 2, minutes: 60, meters: 30_000, heartRate: 150)
        let reading = try await profileBuilder(performance: nil, workouts: [ride]).build(now: TestFixtures.now)
        XCTAssertNil(reading.snapshot.performance)
        XCTAssertEqual(reading.snapshot.sports?[1].loadLastSevenDays, 48, "ohne Puls: Minuten mal 0,8")
    }

    func testLegacyReadingListsSwimWorkoutsAsAllWorkouts() async throws {
        let swim = TestFixtures.workout(daysAgo: 1, meters: 1500)
        let builder = SnapshotBuilder(
            workoutRepository: FakeWorkoutRepository(workouts: [swim]),
            vitalsRepository: FakeVitalsRepository(),
            calendar: TestFixtures.utc
        )
        let reading = try await builder.build(now: TestFixtures.now)
        XCTAssertEqual(reading.allWorkouts, [Workout(swim: swim)])

        let manual = AthleteStateReading(snapshot: reading.snapshot, workouts: [swim], vitalsAvailable: true)
        XCTAssertEqual(manual.allWorkouts.map(\.sport), [.swim])
    }

    func testWorkoutFailureIsAnError() async {
        let builder = SnapshotBuilder(
            workoutRepository: FakeWorkoutRepository(error: TestError(message: "Health gesperrt")),
            vitalsRepository: FakeVitalsRepository(),
            calendar: TestFixtures.utc
        )

        do {
            _ = try await builder.build(now: TestFixtures.now)
            XCTFail("Fehler erwartet")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Health gesperrt")
        }
    }
}
