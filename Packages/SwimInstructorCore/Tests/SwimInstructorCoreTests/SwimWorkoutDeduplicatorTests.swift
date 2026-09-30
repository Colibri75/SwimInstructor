import XCTest
@testable import SwimInstructorCore

final class SwimWorkoutDeduplicatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_780_000_000)

    private func workout(
        startOffset: TimeInterval,
        seconds: TimeInterval,
        meters: Double? = nil,
        laps: Int? = nil,
        heartRate: Double? = nil
    ) -> SwimWorkout {
        let start = base.addingTimeInterval(startOffset)
        return SwimWorkout(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(seconds),
            duration: seconds,
            totalDistanceMeters: meters,
            lapCount: laps,
            totalStrokeCount: nil,
            averageHeartRate: heartRate
        )
    }

    func testOverlappingWorkoutsKeepTheOneWithDistance() {
        let withoutDistance = workout(startOffset: 0, seconds: 3690)
        let withDistance = workout(startOffset: 30, seconds: 3600, meters: 2425)

        let result = SwimWorkoutDeduplicator.deduplicate([withoutDistance, withDistance])

        XCTAssertEqual(result.map(\.id), [withDistance.id])
    }

    func testOrderOfInputDoesNotMatter() {
        let withoutDistance = workout(startOffset: 0, seconds: 3690)
        let withDistance = workout(startOffset: 30, seconds: 3600, meters: 2425)

        let result = SwimWorkoutDeduplicator.deduplicate([withDistance, withoutDistance])

        XCTAssertEqual(result.map(\.id), [withDistance.id])
    }

    func testMoreCompleteWorkoutWinsWhenBothHaveDistance() {
        let plain = workout(startOffset: 0, seconds: 3600, meters: 2000)
        let rich = workout(startOffset: 0, seconds: 3600, meters: 2000, laps: 80, heartRate: 140)

        let result = SwimWorkoutDeduplicator.deduplicate([plain, rich])

        XCTAssertEqual(result.map(\.id), [rich.id])
    }

    func testSeparateWorkoutsOnDifferentTimesAreKept() {
        let morning = workout(startOffset: 0, seconds: 1800, meters: 1000)
        let evening = workout(startOffset: 8 * 3600, seconds: 1800, meters: 900)

        let result = SwimWorkoutDeduplicator.deduplicate([morning, evening])

        XCTAssertEqual(result.count, 2)
    }

    func testBackToBackWorkoutsWithoutOverlapAreKept() {
        let first = workout(startOffset: 0, seconds: 1800, meters: 1000)
        let second = workout(startOffset: 1800, seconds: 1800, meters: 1000)

        XCTAssertEqual(SwimWorkoutDeduplicator.deduplicate([first, second]).count, 2)
    }

    func testSmallOverlapBelowHalfOfShorterWorkoutIsKept() {
        // 10 Minuten Überlappung bei 30 Minuten Dauer: 33 % - kein Duplikat.
        let first = workout(startOffset: 0, seconds: 1800, meters: 1000)
        let second = workout(startOffset: 1200, seconds: 1800, meters: 1000)

        XCTAssertEqual(SwimWorkoutDeduplicator.deduplicate([first, second]).count, 2)
    }

    func testEmptyInputYieldsEmptyOutput() {
        XCTAssertTrue(SwimWorkoutDeduplicator.deduplicate([]).isEmpty)
    }
}
