import XCTest
@testable import SwimInstructorCore

final class PlanHistoryTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-history-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("plan-history.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    func testEmptyWhenNothingStored() {
        XCTAssertEqual(FilePlanHistory(fileURL: fileURL).load(), [])
    }

    func testRecordedPlansSurviveANewInstanceAndAreSortedOldestFirst() throws {
        let history = FilePlanHistory(fileURL: fileURL)
        try history.record(TestFixtures.response(date: "2026-09-30"))
        try history.record(TestFixtures.response(date: "2026-09-28"))
        try history.record(TestFixtures.response(date: "2026-09-29"))

        let reloaded = FilePlanHistory(fileURL: fileURL).load()

        XCTAssertEqual(reloaded.map(\.date), ["2026-09-28", "2026-09-29", "2026-09-30"])
        XCTAssertEqual(reloaded.first, TestFixtures.response(date: "2026-09-28"))
    }

    func testFirstPlanOfADayWins() throws {
        let history = FilePlanHistory(fileURL: fileURL)
        let morning = TestFixtures.response(date: "2026-09-30")
        let evening = PlanResponse(
            source: .claude,
            date: "2026-09-30",
            generatedAt: TestFixtures.now.addingTimeInterval(8 * 3600),
            stale: false,
            plan: TrainingPlan(sessionType: .rest, intensity: .rest, rationale: "Nach dem Training", totalDistanceMeters: 0, estimatedDurationMinutes: 0, sets: [], coachNotes: []),
            adjustments: []
        )

        try history.record(morning)
        try history.record(evening)

        XCTAssertEqual(history.load(), [morning])
    }

    func testFallbackPlansAreNotRecorded() throws {
        let history = FilePlanHistory(fileURL: fileURL)

        try history.record(TestFixtures.response(date: "2026-09-29", source: .fallback, stale: true))

        XCTAssertEqual(history.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testOldestEntriesFallOutBeyondTheLimit() throws {
        let history = FilePlanHistory(fileURL: fileURL, maxEntries: 3)
        for day in 1...5 {
            try history.record(TestFixtures.response(date: String(format: "2026-09-%02d", day)))
        }

        XCTAssertEqual(history.load().map(\.date), ["2026-09-03", "2026-09-04", "2026-09-05"])
    }

    func testCorruptFileCountsAsEmptyAndIsReplacedOnNextRecord() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("kein json".utf8).write(to: fileURL)
        let history = FilePlanHistory(fileURL: fileURL)

        XCTAssertEqual(history.load(), [])
        try history.record(TestFixtures.response(date: "2026-09-30"))

        XCTAssertEqual(history.load().map(\.date), ["2026-09-30"])
    }
}
