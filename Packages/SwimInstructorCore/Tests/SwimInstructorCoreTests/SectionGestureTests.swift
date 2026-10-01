import XCTest
@testable import SwimInstructorCore

final class SectionGestureTests: XCTestCase {
    private let start = TestFixtures.now

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testQuickPauseAndResumeIsTheGesture() {
        var gesture = SectionGesture()

        gesture.didPause(at: at(0))

        XCTAssertTrue(gesture.didResume(at: at(1.5)))
    }

    func testPauseOfExactlyTheLimitStillCounts() {
        var gesture = SectionGesture()
        gesture.didPause(at: at(0))

        XCTAssertTrue(gesture.didResume(at: at(SectionGesture.maxPause)))
    }

    func testARealBreakIsNotAGesture() {
        var gesture = SectionGesture()
        gesture.didPause(at: at(0))

        XCTAssertFalse(gesture.didResume(at: at(SectionGesture.maxPause + 0.1)))
        XCTAssertFalse(gesture.didResume(at: at(60)))
    }

    func testPauseByTheOnScreenButtonIsNeverAGesture() {
        var gesture = SectionGesture()
        gesture.didPause(at: at(0), byButtonOnScreen: true)

        XCTAssertFalse(gesture.didResume(at: at(1)))
    }

    func testResumeWithoutPauseIsNothing() {
        var gesture = SectionGesture()

        // Zum Beispiel der erste "läuft"-Zustand beim Start der Einheit.
        XCTAssertFalse(gesture.didResume(at: at(0)))
    }

    func testEachPauseCountsOnlyOnce() {
        var gesture = SectionGesture()
        gesture.didPause(at: at(0))
        XCTAssertTrue(gesture.didResume(at: at(1)))

        XCTAssertFalse(gesture.didResume(at: at(2)))
    }

    func testResetForgetsAPendingPause() {
        var gesture = SectionGesture()
        gesture.didPause(at: at(0))

        gesture.reset()

        XCTAssertFalse(gesture.didResume(at: at(1)))
    }
}
