import XCTest
@testable import SwimInstructorCore

final class SnapshotBuilderTests: XCTestCase {
    func testReadsWindowsTheCalculatorNeeds() async throws {
        let workouts = FakeWorkoutRepository(workouts: [TestFixtures.workout(daysAgo: 2, meters: 1000)])
        let vitals = FakeVitalsRepository()
        let builder = SnapshotBuilder(workoutRepository: workouts, vitalsRepository: vitals, calendar: TestFixtures.utc)

        _ = try await builder.build(now: TestFixtures.now)

        // Tag 0 bis 55 für Workouts, Tag 0 bis 30 für Tageswerte, jeweils ab Mitternacht.
        XCTAssertEqual(workouts.requestedStart, TestFixtures.date(daysAgo: 55, hour: 0))
        XCTAssertEqual(vitals.requestedStart, TestFixtures.date(daysAgo: 30, hour: 0))
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
    }

    func testMissingVitalsStillProduceSnapshot() async throws {
        let builder = SnapshotBuilder(
            workoutRepository: FakeWorkoutRepository(workouts: [TestFixtures.workout(daysAgo: 1, meters: 1500)]),
            vitalsRepository: FakeVitalsRepository(error: TestError(message: "kein Zugriff")),
            calendar: TestFixtures.utc
        )

        let reading = try await builder.build(now: TestFixtures.now)

        XCTAssertFalse(reading.vitalsAvailable)
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
