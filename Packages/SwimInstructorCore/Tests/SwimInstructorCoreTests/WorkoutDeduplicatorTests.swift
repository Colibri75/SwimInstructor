import XCTest
@testable import SwimInstructorCore

final class WorkoutDeduplicatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func workout(
        _ sport: SportID, offset: TimeInterval = 0, seconds: TimeInterval = 3600,
        distance: Double? = nil, heartRate: Double? = nil, energy: Double? = nil,
        metrics: [WorkoutMetric: Double] = [:]
    ) -> Workout {
        Workout(
            id: UUID(), sport: sport, startDate: start.addingTimeInterval(offset),
            endDate: start.addingTimeInterval(offset + seconds), duration: seconds,
            distanceMeters: distance, averageHeartRate: heartRate, activeEnergyKilocalories: energy, metrics: metrics
        )
    }

    func testSameSportOverlapKeepsTheMoreCompleteOne() {
        let sparse = workout(.run, heartRate: 140)
        let complete = workout(.run, offset: 60, distance: 10_000)

        let result = WorkoutDeduplicator.deduplicate([sparse, complete])

        XCTAssertEqual(result.map(\.id), [complete.id])
    }

    func testFirstOneStaysOnTie() {
        let first = workout(.bike, distance: 30_000)
        let second = workout(.bike, offset: 120, distance: 30_000)
        XCTAssertEqual(WorkoutDeduplicator.deduplicate([second, first]).map(\.id), [first.id])
    }

    func testDifferentSportsAlwaysStay() {
        // Koppeltraining: Rad bis 60 min, Lauf ab 55 min. Die Überschneidung ist kein Duplikat.
        let bike = workout(.bike, distance: 30_000)
        let run = workout(.run, offset: 3300, seconds: 1800, distance: 5000)
        let sameTimeSwim = workout(.swim, distance: 2000)
        XCTAssertEqual(WorkoutDeduplicator.deduplicate([run, bike, sameTimeSwim]).count, 3)
    }

    func testSmallOrNoOverlapIsNoDuplicate() {
        let first = workout(.run)
        let touching = workout(.run, offset: 3600)
        let slightlyOverlapping = workout(.run, offset: 2000)
        XCTAssertEqual(WorkoutDeduplicator.deduplicate([first, touching]).count, 2)
        XCTAssertEqual(WorkoutDeduplicator.deduplicate([first, slightlyOverlapping]).count, 2)
        XCTAssertFalse(WorkoutDeduplicator.overlapsSignificantly(workout(.run, seconds: 0), workout(.run)))
    }

    func testCompletenessWeighsDistanceHighest() {
        XCTAssertEqual(WorkoutDeduplicator.completeness(of: workout(.run)), 0)
        XCTAssertEqual(WorkoutDeduplicator.completeness(of: workout(.run, distance: 0)), 0)
        XCTAssertEqual(
            WorkoutDeduplicator.completeness(of: workout(.run, distance: 1, heartRate: 1, energy: 1, metrics: [.averagePower: 1])),
            8 + 2 + 1 + 1
        )
    }
}
