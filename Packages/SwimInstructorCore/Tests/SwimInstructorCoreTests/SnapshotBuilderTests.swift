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
