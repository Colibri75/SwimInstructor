import XCTest
@testable import SwimInstructorCore

final class DailyWishTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        suite = "wish-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testWishIsStoredPerDayAndSurvivesANewInstance() {
        UserDefaultsDailyWishStore(defaults: defaults).setWish("Heute lieber Technik", for: "2026-09-30")

        let reloaded = UserDefaultsDailyWishStore(defaults: defaults)
        XCTAssertEqual(reloaded.wish(for: "2026-09-30"), "Heute lieber Technik")
        XCTAssertNil(reloaded.wish(for: "2026-10-01"))
    }

    func testEmptyOrBlankTextRemovesTheWish() {
        let store = UserDefaultsDailyWishStore(defaults: defaults)
        store.setWish("etwas", for: "2026-09-30")

        store.setWish("  \n ", for: "2026-09-30")

        XCTAssertNil(store.wish(for: "2026-09-30"))
        store.setWish("noch mal", for: "2026-09-30")
        store.setWish(nil, for: "2026-09-30")
        XCTAssertNil(store.wish(for: "2026-09-30"))
    }

    func testWishIsTrimmedAndCutToTheMaximumLength() {
        let store = UserDefaultsDailyWishStore(defaults: defaults)

        store.setWish("  " + String(repeating: "x", count: DailyWish.maxLength + 40) + "  ", for: "2026-09-30")

        XCTAssertEqual(store.wish(for: "2026-09-30")?.count, DailyWish.maxLength)
    }

    func testOnlyTheNewestDaysAreKept() {
        let store = UserDefaultsDailyWishStore(defaults: defaults)
        for day in 1...(DailyWish.retainedDays + 3) {
            store.setWish("Tag \(day)", for: String(format: "2026-09-%02d", day))
        }

        XCTAssertNil(store.wish(for: "2026-09-01"))
        XCTAssertNil(store.wish(for: "2026-09-03"))
        XCTAssertEqual(store.wish(for: "2026-09-04"), "Tag 4")
        XCTAssertEqual(store.wish(for: String(format: "2026-09-%02d", DailyWish.retainedDays + 3)), "Tag \(DailyWish.retainedDays + 3)")
    }
}
