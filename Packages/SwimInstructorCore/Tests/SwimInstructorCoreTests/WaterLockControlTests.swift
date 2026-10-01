import XCTest
@testable import SwimInstructorCore

final class WaterLockControlTests: XCTestCase {
    private let start = TestFixtures.now

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testNothingHappensWhileLocked() {
        var control = WaterLockControl()

        XCTAssertNil(control.update(isRunning: true, isLocked: true, now: at(0)))
        XCTAssertNil(control.update(isRunning: true, isLocked: true, now: at(60)))
        XCTAssertFalse(control.acceptsCrown(now: at(60)))
    }

    func testCrownIsIgnoredRightAfterUnlockingAndAcceptedAfterTheSettleTime() {
        var control = WaterLockControl()
        _ = control.update(isRunning: true, isLocked: true, now: at(0))

        _ = control.update(isRunning: true, isLocked: false, now: at(10))

        XCTAssertFalse(control.acceptsCrown(now: at(10)))
        XCTAssertFalse(control.acceptsCrown(now: at(10.5)))
        XCTAssertTrue(control.acceptsCrown(now: at(11)))
    }

    func testRelocksAfterTheIdleTimeWithoutInput() {
        var control = WaterLockControl()
        _ = control.update(isRunning: true, isLocked: false, now: at(0))

        XCTAssertNil(control.update(isRunning: true, isLocked: false, now: at(19)))
        XCTAssertEqual(control.update(isRunning: true, isLocked: false, now: at(20)), .lock)
    }

    func testInputPostponesTheAutomaticLock() {
        var control = WaterLockControl()
        _ = control.update(isRunning: true, isLocked: false, now: at(0))

        control.noteInput(now: at(15))

        XCTAssertNil(control.update(isRunning: true, isLocked: false, now: at(30)))
        XCTAssertEqual(control.update(isRunning: true, isLocked: false, now: at(35)), .lock)
    }

    func testLockingAgainResetsEverything() {
        var control = WaterLockControl()
        _ = control.update(isRunning: true, isLocked: false, now: at(0))
        XCTAssertTrue(control.acceptsCrown(now: at(5)))

        _ = control.update(isRunning: true, isLocked: true, now: at(6))

        XCTAssertFalse(control.acceptsCrown(now: at(7)))
        // Der nächste Entsperr-Vorgang beginnt wieder mit der Beruhigungszeit.
        _ = control.update(isRunning: true, isLocked: false, now: at(30))
        XCTAssertFalse(control.acceptsCrown(now: at(30.2)))
    }

    func testPausedOrStoppedWorkoutNeverLocksOrAcceptsTheCrown() {
        var control = WaterLockControl()
        _ = control.update(isRunning: true, isLocked: false, now: at(0))

        XCTAssertNil(control.update(isRunning: false, isLocked: false, now: at(100)))
        XCTAssertFalse(control.acceptsCrown(now: at(100)))
    }

    func testInputWithoutUnlockIsIgnored() {
        var control = WaterLockControl()
        control.noteInput(now: at(5))

        XCTAssertFalse(control.acceptsCrown(now: at(10)))
    }

    func testOnlyAnUpwardTurnOfEnoughClicksAdvances() {
        XCTAssertFalse(WaterLockControl.isAdvance(crownValue: 0))
        XCTAssertFalse(WaterLockControl.isAdvance(crownValue: -1))
        XCTAssertTrue(WaterLockControl.isAdvance(crownValue: -2))
        XCTAssertTrue(WaterLockControl.isAdvance(crownValue: -3.5))
        // Nach unten gedreht: nichts.
        XCTAssertFalse(WaterLockControl.isAdvance(crownValue: 2))
        XCTAssertFalse(WaterLockControl.isAdvance(crownValue: 10))
    }
}
