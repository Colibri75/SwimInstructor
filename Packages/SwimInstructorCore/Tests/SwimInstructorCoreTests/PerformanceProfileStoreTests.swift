import XCTest
@testable import SwimInstructorCore

final class PerformanceProfileStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: UserDefaultsPerformanceProfileStore!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: "PerformanceProfileStoreTests-\(UUID().uuidString)"))
        store = UserDefaultsPerformanceProfileStore(defaults: defaults)
    }

    func testStartsEmptyAndRecordsConfirmedValuesWithHistory() {
        XCTAssertEqual(store.profile(), .empty)

        XCTAssertTrue(store.record(TestFixtures.performance(.criticalSwimPace, 112, .tested, sport: .swim, daysAgo: 40)))
        XCTAssertTrue(store.record(TestFixtures.performance(.criticalSwimPace, 105, .tested, sport: .swim, daysAgo: 2)))
        XCTAssertTrue(store.record(TestFixtures.performance(.maxHeartRate, 191, .manual)))

        XCTAssertEqual(store.profile().history(of: .criticalSwimPace, sport: .swim).map(\.value), [112, 105])
        XCTAssertEqual(UserDefaultsPerformanceProfileStore(defaults: defaults).profile().values.count, 3, "liegt in den Einstellungen")
    }

    func testRejectsEstimatesUnknownAndImplausibleValues() {
        XCTAssertFalse(store.record(TestFixtures.performance(.maxHeartRate, 190, .estimated)), "Schätzungen speichert das Profil nicht")
        XCTAssertFalse(store.record(TestFixtures.performance(.thresholdHeartRate, 170, .formula, sport: .run)))
        XCTAssertFalse(store.record(TestFixtures.performance(.criticalSwimPace, 105, .tested, sport: .run)), "Laufen kennt keine CSS")
        XCTAssertFalse(store.record(TestFixtures.performance(.thresholdHeartRate, 170, .tested)), "Schwellenpuls gehört zu einer Sportart")
        XCTAssertFalse(store.record(TestFixtures.performance(.thresholdHeartRate, 250, .tested, sport: .run)), "Tippfehler")
        XCTAssertEqual(store.profile(), .empty)
    }

    func testResetAndUnreadableDataGiveAnEmptyProfile() {
        store.record(TestFixtures.performance(.maxHeartRate, 191, .manual))
        store.reset()
        XCTAssertEqual(store.profile(), .empty)

        defaults.set(Data("kaputt".utf8), forKey: UserDefaultsPerformanceProfileStore.storageKey)
        XCTAssertEqual(store.profile(), .empty)
    }
}
