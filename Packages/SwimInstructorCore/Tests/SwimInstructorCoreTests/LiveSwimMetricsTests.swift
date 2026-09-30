import XCTest
@testable import SwimInstructorCore

final class LiveSwimMetricsTests: XCTestCase {
    func testPaceIncludesRest() {
        let metrics = LiveSwimMetrics(elapsed: 1200, distanceMeters: 800)

        XCTAssertEqual(metrics.averagePaceSecondsPer100m, 150)
    }

    func testNoPaceWithoutDistanceOrTime() {
        XCTAssertNil(LiveSwimMetrics.zero.averagePaceSecondsPer100m)
        XCTAssertNil(LiveSwimMetrics(elapsed: 0, distanceMeters: 100).averagePaceSecondsPer100m)
    }

    func testStrokesPerLap() {
        XCTAssertEqual(LiveSwimMetrics(laps: 4, strokes: 72).strokesPerLap, 18)
        XCTAssertNil(LiveSwimMetrics(laps: 0, strokes: 10).strokesPerLap)
        XCTAssertNil(LiveSwimMetrics(laps: 4, strokes: 0).strokesPerLap)
    }

    func testLapsFollowEventsOrDistanceWhicheverIsAhead() {
        XCTAssertEqual(LiveSwimMetrics.laps(lapEvents: 4, distanceMeters: 100, poolLengthMeters: 25), 4)
        // Strecke schon da, Lap-Event noch nicht.
        XCTAssertEqual(LiveSwimMetrics.laps(lapEvents: 3, distanceMeters: 100, poolLengthMeters: 25), 4)
        XCTAssertEqual(LiveSwimMetrics.laps(lapEvents: 0, distanceMeters: 60, poolLengthMeters: 25), 2)
        XCTAssertEqual(LiveSwimMetrics.laps(lapEvents: 2, distanceMeters: 100, poolLengthMeters: 0), 2)
    }

    func testPoolLengthIsClamped() {
        XCTAssertEqual(PoolLength.clamped(25), 25)
        XCTAssertEqual(PoolLength.clamped(3), 10)
        XCTAssertEqual(PoolLength.clamped(400), 100)
        XCTAssertTrue(PoolLength.presets.allSatisfy { PoolLength.range.contains($0) })
        XCTAssertTrue(PoolLength.range.contains(PoolLength.defaultMeters))
    }
}
