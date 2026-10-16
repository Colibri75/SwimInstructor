import XCTest
@testable import SwimInstructorCore

final class PauseReportTests: XCTestCase {
    private func report(_ kind: PauseReport.Kind = .sick, from: String, to: String?) -> PauseReport {
        PauseReport(kind: kind, from: from, to: to, reportedAt: TestFixtures.now)
    }

    func testContainsItsDaysAndAnOngoingPauseEveryDayAfterItsStart() {
        let closed = report(from: "2026-09-28", to: "2026-09-30")
        XCTAssertFalse(closed.contains("2026-09-27"))
        XCTAssertTrue(closed.contains("2026-09-28"))
        XCTAssertTrue(closed.contains("2026-09-30"))
        XCTAssertFalse(closed.contains("2026-10-01"))

        let ongoing = report(from: "2026-09-28", to: nil)
        XCTAssertFalse(ongoing.contains("2026-09-27"))
        XCTAssertTrue(ongoing.contains("2026-12-24"))
    }

    func testGoesIntoTheSnapshotWhileItStillMatters() {
        // Kommend und laufend: ja.
        XCTAssertEqual(
            report(.vacation, from: "2026-10-10", to: "2026-10-17").snapshotSummary(today: "2026-09-30", calendar: TestFixtures.utc),
            AthleteStateSnapshot.ReportedPauseSummary(kind: "vacation", from: "2026-10-10", to: "2026-10-17")
        )
        XCTAssertEqual(
            report(from: "2026-09-28", to: nil).snapshotSummary(today: "2026-09-30", calendar: TestFixtures.utc),
            AthleteStateSnapshot.ReportedPauseSummary(kind: "sick", from: "2026-09-28", to: nil)
        )
        // Vorbei: noch sieben Tage lang (danach plant der Server ohnehin wieder normal), dann nicht mehr.
        XCTAssertNotNil(report(from: "2026-09-20", to: "2026-09-23").snapshotSummary(today: "2026-09-30", calendar: TestFixtures.utc))
        XCTAssertNil(report(from: "2026-09-20", to: "2026-09-22").snapshotSummary(today: "2026-09-30", calendar: TestFixtures.utc))
    }

    func testAnInvalidPauseStaysOutOfTheSnapshot() {
        XCTAssertNil(report(from: "2026-09-30", to: "2026-09-28").snapshotSummary(today: "2026-09-30", calendar: TestFixtures.utc))
    }
}
