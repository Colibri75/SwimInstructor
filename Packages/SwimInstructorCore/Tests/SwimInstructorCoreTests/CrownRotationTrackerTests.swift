import XCTest
@testable import SwimInstructorCore

final class CrownRotationTrackerTests: XCTestCase {
    private let start = TestFixtures.now

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testAdvancesAfterEnoughRotationWhenUnlocked() {
        var tracker = CrownRotationTracker()

        XCTAssertFalse(tracker.moved(to: 1, isLocked: false, at: at(0)))
        XCTAssertFalse(tracker.moved(to: 2, isLocked: false, at: at(0.1)))
        XCTAssertTrue(tracker.moved(to: 3, isLocked: false, at: at(0.2)))
        XCTAssertEqual(tracker.travel, 0)
    }

    func testDirectionDoesNotMatter() {
        var down = CrownRotationTracker()
        var up = CrownRotationTracker()

        XCTAssertFalse(down.moved(to: -2, isLocked: false, at: at(0)))
        XCTAssertTrue(down.moved(to: -3, isLocked: false, at: at(0.1)))
        XCTAssertFalse(up.moved(to: 2, isLocked: false, at: at(0)))
        XCTAssertTrue(up.moved(to: 3, isLocked: false, at: at(0.1)))
    }

    func testBackAndForthCountsAsTravel() {
        var tracker = CrownRotationTracker()

        XCTAssertFalse(tracker.moved(to: 2, isLocked: false, at: at(0)))
        XCTAssertTrue(tracker.moved(to: 1, isLocked: false, at: at(0.1)))
    }

    func testWaterLockNeedsALongerTurn() {
        var tracker = CrownRotationTracker()

        // Drei Einheiten reichen entsperrt, bei Wassersperre noch nicht (die entsperrende Drehung zählt nicht).
        for step in 1...7 {
            XCTAssertFalse(tracker.moved(to: Double(step), isLocked: true, at: at(Double(step) * 0.1)))
        }
        XCTAssertTrue(tracker.moved(to: 8, isLocked: true, at: at(0.8)))
    }

    func testPauseInTheTurnStartsOver() {
        var tracker = CrownRotationTracker()
        _ = tracker.moved(to: 2, isLocked: false, at: at(0))

        // 5 Sekunden später: Der erste Teil ist verfallen, 2 weitere Einheiten reichen nicht.
        XCTAssertFalse(tracker.moved(to: 4, isLocked: false, at: at(5)))
        XCTAssertEqual(tracker.travel, 2)
    }

    func testIdleResetClearsTheProgress() {
        var tracker = CrownRotationTracker()
        _ = tracker.moved(to: 2, isLocked: false, at: at(0))
        XCTAssertEqual(tracker.progress(isLocked: false), 2.0 / 3.0, accuracy: 0.0001)

        tracker.resetIfIdle(at: at(0.5))
        XCTAssertEqual(tracker.travel, 2)

        tracker.resetIfIdle(at: at(2))
        XCTAssertEqual(tracker.travel, 0)
        XCTAssertEqual(tracker.progress(isLocked: false), 0)
    }

    func testProgressIsRelativeToTheThresholdAndStopsAtOne() {
        var tracker = CrownRotationTracker()
        _ = tracker.moved(to: 2, isLocked: true, at: at(0))

        XCTAssertEqual(tracker.progress(isLocked: true), 2.0 / 8.0, accuracy: 0.0001)
        XCTAssertEqual(tracker.progress(isLocked: false), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(CrownRotationTracker().progress(isLocked: false), 0)
    }

    func testResetByTheViewIsNotCountedAsRotation() {
        var tracker = CrownRotationTracker()
        XCTAssertTrue(tracker.moved(to: 3, isLocked: false, at: at(0)))

        // Die Ansicht setzt die Crown auf 0 zurück.
        tracker.rebase()
        XCTAssertFalse(tracker.moved(to: 0, isLocked: false, at: at(0.1)))
        XCTAssertEqual(tracker.travel, 0)
    }

    func testHugeJumpIsTreatedAsAResetNotARotation() {
        var tracker = CrownRotationTracker()
        _ = tracker.moved(to: 40, isLocked: false, at: at(0))

        XCTAssertFalse(tracker.moved(to: 0, isLocked: false, at: at(0.1)))
        XCTAssertEqual(tracker.travel, 0)
    }

    func testNoMovementNeverAdvances() {
        var tracker = CrownRotationTracker()

        XCTAssertFalse(tracker.moved(to: 0, isLocked: false, at: at(0)))
        XCTAssertFalse(tracker.moved(to: 0, isLocked: true, at: at(1)))
    }
}
