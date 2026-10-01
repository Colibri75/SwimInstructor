import XCTest
@testable import SwimInstructorCore

final class CrownRotationTrackerTests: XCTestCase {
    private let start = TestFixtures.now
    private let unlocked = CrownRotationTracker.unlockedThreshold
    private let locked = CrownRotationTracker.lockedThreshold

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// Dreht in Schritten von 1 in die Richtung (`up` = nach oben) und liefert das erste Ergebnis.
    private func turn(
        _ tracker: inout CrownRotationTracker,
        up: Bool,
        units: Int,
        isLocked: Bool,
        from base: Double = 0
    ) -> CrownStep? {
        let sign = (up == CrownRotationTracker.upIsPositive) ? 1.0 : -1.0
        var result: CrownStep?
        for step in 1...units {
            let value = base + sign * Double(step)
            if let reached = tracker.moved(to: value, isLocked: isLocked, at: at(Double(step) * 0.1)) {
                result = reached
                break
            }
        }
        return result
    }

    func testThresholdsAreWellAboveWhatFeltTooSensitive() {
        XCTAssertGreaterThanOrEqual(unlocked, 8)
        XCTAssertGreaterThan(locked, unlocked)
    }

    func testTurningUpAdvancesAfterEnoughRotationWhenUnlocked() {
        var tracker = CrownRotationTracker()

        XCTAssertNil(turn(&tracker, up: true, units: Int(unlocked) - 1, isLocked: false))
        XCTAssertEqual(tracker.step, .next)
        XCTAssertEqual(turn(&tracker, up: true, units: 1, isLocked: false, from: unlocked - 1), .next)
        XCTAssertEqual(tracker.travel, 0)
        XCTAssertNil(tracker.step)
    }

    func testTurningDownGoesBack() {
        var tracker = CrownRotationTracker()

        XCTAssertEqual(turn(&tracker, up: false, units: Int(unlocked), isLocked: false), .previous)
    }

    func testWaterLockNeedsALongerTurn() {
        var tracker = CrownRotationTracker()

        // Was entsperrt reicht, löst bei Wassersperre noch nichts aus.
        XCTAssertNil(turn(&tracker, up: true, units: Int(locked) - 1, isLocked: true))
        XCTAssertEqual(turn(&tracker, up: true, units: 1, isLocked: true, from: locked - 1), .next)
    }

    func testChangingDirectionStartsOver() {
        var tracker = CrownRotationTracker()
        XCTAssertNil(turn(&tracker, up: true, units: Int(unlocked) - 2, isLocked: false))

        // Zurückdrehen zählt nicht die vorige Strecke ab, sondern beginnt neu in die andere Richtung.
        let backValue = (CrownRotationTracker.upIsPositive ? -1.0 : 1.0)
        XCTAssertNil(tracker.moved(to: Double(unlocked - 2) * (CrownRotationTracker.upIsPositive ? 1 : -1) + backValue, isLocked: false, at: at(1)))
        XCTAssertEqual(tracker.step, .previous)
        XCTAssertEqual(abs(tracker.travel), 1)
    }

    func testPauseInTheTurnStartsOver() {
        var tracker = CrownRotationTracker()
        _ = tracker.moved(to: CrownRotationTracker.upIsPositive ? 2 : -2, isLocked: false, at: at(0))

        // 5 Sekunden später: Der erste Teil ist verfallen.
        XCTAssertNil(tracker.moved(to: CrownRotationTracker.upIsPositive ? 4 : -4, isLocked: false, at: at(5)))
        XCTAssertEqual(abs(tracker.travel), 2)
    }

    func testIdleResetClearsTheProgress() {
        var tracker = CrownRotationTracker()
        _ = tracker.moved(to: CrownRotationTracker.upIsPositive ? 2 : -2, isLocked: false, at: at(0))
        XCTAssertEqual(tracker.progress(isLocked: false), 2.0 / unlocked, accuracy: 0.0001)

        tracker.resetIfIdle(at: at(0.5))
        XCTAssertEqual(abs(tracker.travel), 2)

        tracker.resetIfIdle(at: at(CrownRotationTracker.idleReset + 1))
        XCTAssertEqual(tracker.travel, 0)
        XCTAssertEqual(tracker.progress(isLocked: false), 0)
        XCTAssertNil(tracker.step)
    }

    func testProgressIsRelativeToTheThresholdAndStopsAtOne() {
        var tracker = CrownRotationTracker()
        _ = tracker.moved(to: CrownRotationTracker.upIsPositive ? 2 : -2, isLocked: true, at: at(0))

        XCTAssertEqual(tracker.progress(isLocked: true), 2.0 / locked, accuracy: 0.0001)
        XCTAssertEqual(tracker.progress(isLocked: false), 2.0 / unlocked, accuracy: 0.0001)
        XCTAssertEqual(CrownRotationTracker().progress(isLocked: false), 0)
    }

    func testResetByTheViewIsNotCountedAsRotation() {
        var tracker = CrownRotationTracker()
        XCTAssertNotNil(turn(&tracker, up: true, units: Int(unlocked), isLocked: false))

        // Die Ansicht setzt die Crown auf 0 zurück.
        tracker.rebase()
        XCTAssertNil(tracker.moved(to: 0, isLocked: false, at: at(5)))
        XCTAssertEqual(tracker.travel, 0)
    }

    func testHugeJumpIsTreatedAsAResetNotARotation() {
        var tracker = CrownRotationTracker()
        _ = tracker.moved(to: 40, isLocked: false, at: at(0))

        XCTAssertNil(tracker.moved(to: 0, isLocked: false, at: at(0.1)))
        XCTAssertEqual(tracker.travel, 0)
    }

    func testNoMovementNeverChangesTheSection() {
        var tracker = CrownRotationTracker()

        XCTAssertNil(tracker.moved(to: 0, isLocked: false, at: at(0)))
        XCTAssertNil(tracker.moved(to: 0, isLocked: true, at: at(1)))
    }

    func testStepMapsToSectionDirection() {
        XCTAssertEqual(CrownStep.next.direction, .next)
        XCTAssertEqual(CrownStep.previous.direction, .previous)
    }

    // MARK: - Nach einem Wechsel

    func testKeepingTurningAfterAChangeDoesNotTriggerAgain() {
        var tracker = CrownRotationTracker()
        let sign = CrownRotationTracker.upIsPositive ? 1.0 : -1.0
        var steps = 0

        // Dreht ohne Pause weiter, mehr als dreimal die Schwelle, alle 0,1 s ein Schritt.
        for step in 1...Int(unlocked * 3) {
            if tracker.moved(to: sign * Double(step), isLocked: false, at: at(Double(step) * 0.1)) != nil { steps += 1 }
        }

        XCTAssertEqual(steps, 1)
        XCTAssertTrue(tracker.isSettling)
        XCTAssertEqual(tracker.progress(isLocked: false), 0)
    }

    func testAfterTheCrownRestedTheNextTurnCountsAgain() {
        var tracker = CrownRotationTracker()
        let sign = CrownRotationTracker.upIsPositive ? 1.0 : -1.0
        for step in 1...Int(unlocked) {
            _ = tracker.moved(to: sign * Double(step), isLocked: false, at: at(Double(step) * 0.1))
        }
        XCTAssertTrue(tracker.isSettling)
        tracker.rebase()

        // Pause länger als die Wartezeit: wieder bereit.
        let resume = Double(Int(unlocked)) * 0.1 + CrownRotationTracker.settleTime + 0.5
        tracker.resetIfIdle(at: at(resume))
        XCTAssertFalse(tracker.isSettling)

        var second: CrownStep?
        for step in 1...Int(unlocked) {
            second = tracker.moved(to: sign * Double(step), isLocked: false, at: at(resume + Double(step) * 0.1)) ?? second
        }
        XCTAssertEqual(second, .next)
    }

    func testTurningDuringTheWaitExtendsIt() {
        var tracker = CrownRotationTracker()
        let sign = CrownRotationTracker.upIsPositive ? 1.0 : -1.0
        for step in 1...Int(unlocked) {
            _ = tracker.moved(to: sign * Double(step), isLocked: false, at: at(Double(step) * 0.1))
        }
        let triggered = Double(Int(unlocked)) * 0.1

        // Kurz vor Ablauf noch ein Schritt: Die Wartezeit beginnt von vorn.
        _ = tracker.moved(to: sign * Double(unlocked + 1), isLocked: false, at: at(triggered + CrownRotationTracker.settleTime - 0.1))
        tracker.resetIfIdle(at: at(triggered + CrownRotationTracker.settleTime + 0.3))

        XCTAssertTrue(tracker.isSettling)
    }
}
