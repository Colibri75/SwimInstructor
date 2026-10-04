import XCTest
@testable import SwimInstructorCore

/// Testergebnisse von der Watch zum iPhone: Format der Übertragung und Eingang bis zur Bestätigung.
final class TestResultSyncTests: XCTestCase {
    private final class MemoryStore: WatchTestResultStoring {
        var stored: [WatchTestResult] = []
        var saves = 0

        func load() -> [WatchTestResult] { stored }

        func save(_ results: [WatchTestResult]) throws {
            stored = results
            saves += 1
        }
    }

    private static func result(
        sport: SportID = .swim,
        testID: String = "css_400_200",
        minutesAgo: Double = 0,
        entries: [String: Double] = ["time_400m": 320, "time_200m": 144]
    ) -> WatchTestResult {
        WatchTestResult(sport: sport, testID: testID, entries: entries, measuredAt: TestFixtures.now.addingTimeInterval(-minutesAgo * 60))
    }

    // MARK: - Übertragung

    func testUserInfoRoundTrip() throws {
        let original = Self.result()

        let userInfo = try TestResultSyncCodec.userInfo(for: original)

        XCTAssertEqual(TestResultSyncCodec.result(from: userInfo), original)
        // WatchConnectivity nimmt nur Property-List-Werte an.
        XCTAssertTrue(PropertyListSerialization.propertyList(userInfo, isValidFor: .binary))
    }

    func testForeignBrokenOrNewerUserInfoIsIgnored() throws {
        XCTAssertNil(TestResultSyncCodec.result(from: [:]))
        XCTAssertNil(TestResultSyncCodec.result(from: ["test_result": Data("kaputt".utf8), "version": 1]))
        XCTAssertNil(TestResultSyncCodec.result(from: ["test_result": "kein Data", "version": 1]))

        var newer = try TestResultSyncCodec.userInfo(for: Self.result())
        newer["version"] = 2
        XCTAssertNil(TestResultSyncCodec.result(from: newer))
    }

    // MARK: - Datei

    func testFileStoreKeepsResultsAcrossLaunches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watch-results-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileWatchTestResultStore(fileURL: directory.appendingPathComponent("watch-test-results.json"))
        XCTAssertEqual(store.load(), [])

        let results = [Self.result(minutesAgo: 10), Self.result(sport: .run, testID: "threshold_30min", entries: ["threshold_heart_rate": 170])]
        try store.save(results)

        XCTAssertEqual(FileWatchTestResultStore(fileURL: directory.appendingPathComponent("watch-test-results.json")).load(), results)
    }

    func testEntryKeysSurviveTheSnakeCaseCoders() throws {
        // Die Coder der App wandeln Schlüssel um, auch die eines Wörterbuchs.
        let original = Self.result(sport: .run, testID: "threshold_30min", entries: ["threshold_heart_rate": 170, "threshold_pace_per_km": 278])

        let data = try PlanResponse.jsonEncoder().encode(original)
        let decoded = try PlanResponse.jsonDecoder().decode(WatchTestResult.self, from: data)

        XCTAssertEqual(decoded.entries, ["threshold_heart_rate": 170, "threshold_pace_per_km": 278])
        XCTAssertEqual(decoded.testID, "threshold_30min")
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"test_id\""))
    }

    // MARK: - Eingang

    @MainActor
    func testInboxKeepsResultsSortedAndOnlyOnce() {
        let store = MemoryStore()
        let inbox = WatchTestResultInbox(store: store)
        let older = Self.result(minutesAgo: 30)
        let newer = Self.result(sport: .bike, testID: "threshold_30min", minutesAgo: 5, entries: ["threshold_heart_rate": 160])

        inbox.receive(newer)
        inbox.receive(older)
        inbox.receive(older)

        XCTAssertEqual(inbox.results, [older, newer])
        XCTAssertEqual(inbox.next, older)
        XCTAssertEqual(store.stored, [older, newer])
        XCTAssertEqual(store.saves, 2)
    }

    @MainActor
    func testInboxIgnoresSportsAndTestsThisVersionDoesNotKnow() {
        let inbox = WatchTestResultInbox(store: MemoryStore())

        inbox.receive(Self.result(sport: "rowing", testID: "time_trial_2000m"))
        inbox.receive(Self.result(testID: "ramp_test"))

        XCTAssertEqual(inbox.results, [])
        XCTAssertNil(inbox.next)
    }

    @MainActor
    func testInboxKeepsOnlyTheNewestResults() {
        let inbox = WatchTestResultInbox(store: MemoryStore())

        for minutes in 0..<(WatchTestResultInbox.limit + 2) {
            inbox.receive(Self.result(minutesAgo: Double(minutes)))
        }

        XCTAssertEqual(inbox.results.count, WatchTestResultInbox.limit)
        XCTAssertEqual(inbox.results.last?.measuredAt, TestFixtures.now)
        XCTAssertEqual(inbox.next?.measuredAt, TestFixtures.now.addingTimeInterval(-Double(WatchTestResultInbox.limit - 1) * 60))
    }

    @MainActor
    func testInboxRemovesAcceptedOrDiscardedResults() {
        let store = MemoryStore()
        let first = Self.result(minutesAgo: 20)
        let second = Self.result(minutesAgo: 10)
        store.stored = [first, second]
        let inbox = WatchTestResultInbox(store: store)
        XCTAssertEqual(inbox.results, [first, second], "Beim Start aus dem Speicher")

        inbox.remove(first.id)
        inbox.remove(UUID())

        XCTAssertEqual(inbox.results, [second])
        XCTAssertEqual(store.stored, [second])
        XCTAssertEqual(store.saves, 1)
    }

    @MainActor
    func testInboxAcceptsATestOfAnyRegisteredSport() throws {
        let registry = try SportRegistry(modules: [SwimModule(), RowingTestModule()])
        let inbox = WatchTestResultInbox(store: MemoryStore(), registry: registry)

        inbox.receive(Self.result(sport: "rowing", testID: "time_trial_2000m", entries: ["time_2000m": 420]))

        XCTAssertEqual(inbox.results.map(\.testID), ["time_trial_2000m"])
    }
}
