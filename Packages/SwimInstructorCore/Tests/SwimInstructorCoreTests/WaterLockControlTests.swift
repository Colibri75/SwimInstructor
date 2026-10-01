import XCTest
@testable import SwimInstructorCore

final class WaterLockControlTests: XCTestCase {
    private let start = TestFixtures.now

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testNothingHappensWhileLocked() {
        var control = WaterLockControl()

        XCTAssertNil(control.update(isRunning: true, isLocked: true, now: at(0)))
        XCTAssertNil(control.update(isRunning: true, isLocked: true, now: at(60)))
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

    func testLockingAgainStartsTheNextUnlockFromScratch() {
        var control = WaterLockControl()
        _ = control.update(isRunning: true, isLocked: false, now: at(0))

        _ = control.update(isRunning: true, isLocked: true, now: at(6))

        // Neu entsperrt bei 30 s: Die 20 Sekunden zählen ab hier, nicht ab dem ersten Entsperren.
        XCTAssertNil(control.update(isRunning: true, isLocked: false, now: at(30)))
        XCTAssertNil(control.update(isRunning: true, isLocked: false, now: at(49)))
        XCTAssertEqual(control.update(isRunning: true, isLocked: false, now: at(50)), .lock)
    }

    func testPausedOrStoppedWorkoutNeverLocks() {
        var control = WaterLockControl()
        _ = control.update(isRunning: true, isLocked: false, now: at(0))

        XCTAssertNil(control.update(isRunning: false, isLocked: false, now: at(100)))
    }

    func testInputWithoutUnlockIsIgnored() {
        var control = WaterLockControl()
        control.noteInput(now: at(5))

        XCTAssertNil(control.update(isRunning: true, isLocked: false, now: at(10)))
        XCTAssertNil(control.update(isRunning: true, isLocked: false, now: at(29)))
        XCTAssertEqual(control.update(isRunning: true, isLocked: false, now: at(30)), .lock)
    }
}
