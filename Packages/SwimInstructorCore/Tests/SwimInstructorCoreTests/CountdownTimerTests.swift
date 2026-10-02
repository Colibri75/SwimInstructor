import XCTest
@testable import SwimInstructorCore

final class CountdownTimerTests: XCTestCase {
    private let start = TestFixtures.now

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testTheDurationsAreThirtySeconds() {
        XCTAssertEqual(TrainingTimers.startCountdownSeconds, 30)
        XCTAssertEqual(TrainingTimers.restBetweenSetsSeconds, 30)
    }

    func testItDoesNotRunBeforeItIsStarted() {
        let timer = CountdownTimer(duration: 30)

        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.remainingSeconds(at: at(5)))
        XCTAssertFalse(timer.isFinished(at: at(100)))
    }

    func testItCountsDownInWholeSecondsRoundedUp() {
        var timer = CountdownTimer(duration: 30)
        timer.start(at: start)

        XCTAssertEqual(timer.remainingSeconds(at: at(0)), 30)
        XCTAssertEqual(timer.remainingSeconds(at: at(0.4)), 30)
        XCTAssertEqual(timer.remainingSeconds(at: at(1)), 29)
        XCTAssertEqual(timer.remainingSeconds(at: at(28.2)), 2)
        XCTAssertEqual(timer.remainingSeconds(at: at(29.9)), 1)
        XCTAssertFalse(timer.isFinished(at: at(29.9)))
    }

    func testItFinishesAtTheEndAndStaysAtZero() {
        var timer = CountdownTimer(duration: 30)
        timer.start(at: start)

        XCTAssertEqual(timer.remainingSeconds(at: at(30)), 0)
        XCTAssertTrue(timer.isFinished(at: at(30)))
        XCTAssertEqual(timer.remainingSeconds(at: at(500)), 0)
    }

    func testCancelStopsItAndStartRestartsIt() {
        var timer = CountdownTimer(duration: 30)
        timer.start(at: start)
        timer.cancel()
        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.remainingSeconds(at: at(5)))

        timer.start(at: at(100))
        XCTAssertEqual(timer.remainingSeconds(at: at(110)), 20)
    }

    func testANegativeDurationCountsAsZero() {
        var timer = CountdownTimer(duration: -5)
        timer.start(at: start)

        XCTAssertTrue(timer.isFinished(at: start))
    }
}
