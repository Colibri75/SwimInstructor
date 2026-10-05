import XCTest
@testable import SwimInstructorCore

final class PlanAdherenceTests: XCTestCase {
    func testSummaryCountsFinishedDaysOnly() {
        let summary = PlanAdherenceCalculator.summary(of: [.followed, .shorter, .longer, .missed, .restKept, .restBroken, .pending])

        XCTAssertEqual(summary.plannedTrainingDays, 4)
        XCTAssertEqual(summary.trainedDays, 3)
        XCTAssertEqual(summary.restDays, 2)
        XCTAssertEqual(summary.restDaysKept, 1)
    }

    func testSummaryOfNothingIsZero() {
        XCTAssertEqual(PlanAdherenceCalculator.summary(of: []), PlanAdherenceSummary(plannedTrainingDays: 0, trainedDays: 0, restDays: 0, restDaysKept: 0))
    }
}
