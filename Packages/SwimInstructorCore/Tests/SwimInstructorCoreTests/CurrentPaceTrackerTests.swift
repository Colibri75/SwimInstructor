import XCTest
@testable import SwimInstructorCore

final class CurrentPaceTrackerTests: XCTestCase {
    func testNoPaceBeforeTheFirstMeasurement() {
        var tracker = CurrentPaceTracker()
        XCTAssertNil(tracker.pace(atElapsed: 10))

        tracker.record(elapsed: 5, distanceMeters: 0)
        XCTAssertNil(tracker.pace(atElapsed: 10))
    }

    func testFirstLapGivesThePaceFromTheStart() {
        var tracker = CurrentPaceTracker()

        tracker.record(elapsed: 30, distanceMeters: 25)

        // 25 m in 30 s = 120 s pro 100 m.
        XCTAssertEqual(tracker.pace(atElapsed: 31) ?? 0, 120, accuracy: 0.001)
    }

    func testPaceFollowsTheRecentLapsAndNotTheWholeSession() {
        var tracker = CurrentPaceTracker()
        // Lange langsam, dann schnell: Die aktuelle Pace zeigt das Schnelle.
        for lap in 1...6 { tracker.record(elapsed: Double(lap) * 40, distanceMeters: Double(lap) * 25) }
        tracker.record(elapsed: 240 + 20, distanceMeters: 175)
        tracker.record(elapsed: 240 + 40, distanceMeters: 200)

        // Fenster 90 s: die Meldungen bei 200, 240, 260, 280 s; frühestens 200 s (Strecke 125 m).
        // 280 s - 200 s = 80 s für 75 m: 106,7 s pro 100 m.
        XCTAssertEqual(tracker.pace(atElapsed: 281) ?? 0, 80.0 / 0.75, accuracy: 0.001)
    }

    func testRestingAtTheWallEndsThePace() {
        var tracker = CurrentPaceTracker()
        tracker.record(elapsed: 30, distanceMeters: 25)
        tracker.record(elapsed: 60, distanceMeters: 50)

        XCTAssertNotNil(tracker.pace(atElapsed: 60 + CurrentPaceTracker.staleAfter))
        XCTAssertNil(tracker.pace(atElapsed: 60 + CurrentPaceTracker.staleAfter + 1))
    }

    func testRepeatedOrShrinkingDistanceIsIgnored() {
        var tracker = CurrentPaceTracker()
        tracker.record(elapsed: 30, distanceMeters: 25)
        tracker.record(elapsed: 40, distanceMeters: 25)
        tracker.record(elapsed: 50, distanceMeters: 20)

        XCTAssertEqual(tracker.pace(atElapsed: 51) ?? 0, 120, accuracy: 0.001)
    }

    func testTooLittleDistanceGivesNoPace() {
        var tracker = CurrentPaceTracker()

        tracker.record(elapsed: 10, distanceMeters: 15)

        XCTAssertNil(tracker.pace(atElapsed: 11))
    }

    func testOldSamplesAreDropped() {
        var tracker = CurrentPaceTracker()
        for lap in 1...100 { tracker.record(elapsed: Double(lap) * 30, distanceMeters: Double(lap) * 25) }

        XCTAssertEqual(tracker.pace(atElapsed: 3001) ?? 0, 120, accuracy: 0.001)
    }
}
