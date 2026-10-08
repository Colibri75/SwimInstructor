import XCTest
@testable import SwimInstructorCore

/// Die Bereiche der Tabs: Standard, gespeicherte Anordnung über Updates, umsortieren, ausblenden, hinzufügen, zurücksetzen.
final class ScreenLayoutTests: XCTestCase {
    private final class MemoryStore: ScreenLayoutStoring {
        var stored: [LayoutScreen: ScreenLayout] = [:]
        var saves = 0

        func load(_ screen: LayoutScreen) -> ScreenLayout? { stored[screen] }

        func save(_ layout: ScreenLayout, for screen: LayoutScreen) throws {
            stored[screen] = layout
            saves += 1
        }

        func remove(_ screen: LayoutScreen) {
            stored[screen] = nil
        }
    }

    private func ids(_ sections: [LayoutSection]) -> [String] {
        sections.map(\.id)
    }

    func testEveryScreenHasUniqueSectionsAndAtLeastOneRequired() {
        for screen in LayoutScreen.allCases {
            let ids = screen.sections.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(screen)")
            XCTAssertFalse(screen.sections.isEmpty, "\(screen)")
        }
        XCTAssertEqual(LayoutScreen.today.section("plan")?.isRequired, true)
        XCTAssertEqual(LayoutScreen.week.section("days")?.isRequired, true)
        XCTAssertEqual(LayoutScreen.macro.section("overview")?.isRequired, true)
    }

    @MainActor
    func testStandardShowsEverySectionInCatalogOrder() {
        let layouts = ScreenLayouts(store: MemoryStore())

        XCTAssertEqual(ids(layouts.visible(.dashboard)), ["statistics", "week", "goal"])
        XCTAssertEqual(ids(layouts.visible(.history)), ["workouts", "summary", "chart", "days"])
        XCTAssertTrue(layouts.hidden(.today).isEmpty)
        XCTAssertTrue(layouts.isStandard(.today))
    }

    @MainActor
    func testMoveHideShowAreSavedPerScreen() {
        let store = MemoryStore()
        let layouts = ScreenLayouts(store: store)

        layouts.move(.dashboard, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(ids(layouts.visible(.dashboard)), ["goal", "statistics", "week"])

        layouts.hide(.dashboard, section: "week")
        XCTAssertEqual(ids(layouts.visible(.dashboard)), ["goal", "statistics"])
        XCTAssertEqual(ids(layouts.hidden(.dashboard)), ["week"])

        layouts.show(.dashboard, section: "week")
        XCTAssertEqual(ids(layouts.visible(.dashboard)), ["goal", "statistics", "week"])
        XCTAssertTrue(layouts.hidden(.dashboard).isEmpty)

        XCTAssertEqual(store.stored[.dashboard]?.visible, ["goal", "statistics", "week"])
        XCTAssertNil(store.stored[.history])
        XCTAssertEqual(ids(ScreenLayouts(store: store).visible(.dashboard)), ["goal", "statistics", "week"])
    }

    @MainActor
    func testRequiredSectionsCannotBeHidden() {
        let layouts = ScreenLayouts(store: MemoryStore())

        layouts.hide(.today, section: "plan")
        layouts.hide(.week, atOffsets: IndexSet(layouts.layout(.week).visible.indices))

        XCTAssertTrue(ids(layouts.visible(.today)).contains("plan"))
        XCTAssertEqual(ids(layouts.visible(.week)), ["days"])
        XCTAssertEqual(ids(layouts.hidden(.week)), ["summary", "macroTarget", "overview", "planning"])
    }

    @MainActor
    func testMoveByOneStepsAndStopsAtTheEdges() {
        let layouts = ScreenLayouts(store: MemoryStore())

        layouts.move(.history, section: "days", by: -1)
        XCTAssertEqual(ids(layouts.visible(.history)), ["workouts", "summary", "days", "chart"])
        layouts.move(.history, section: "workouts", by: -1)
        XCTAssertEqual(ids(layouts.visible(.history)), ["workouts", "summary", "days", "chart"])
    }

    @MainActor
    func testResetRestoresTheStandard() {
        let store = MemoryStore()
        let layouts = ScreenLayouts(store: store)
        layouts.hide(.history, section: "chart")

        layouts.reset(.history)

        XCTAssertTrue(layouts.isStandard(.history))
        XCTAssertNil(store.stored[.history])
    }

    func testStoredLayoutSurvivesUpdates() {
        // Unbekannte und doppelte Bereiche fallen weg, ein ausgeblendeter Pflichtbereich wird wieder angezeigt, und ein
        // neuer Bereich ("chart") erscheint hinter seinem Vorgänger aus dem Standard.
        let stored = ScreenLayout(visible: ["days", "gone", "workouts", "days"], hidden: ["summary", "old"])
        let updated = stored.updated(for: .history)

        XCTAssertEqual(updated.visible, ["days", "workouts", "chart"])
        XCTAssertEqual(updated.hidden, ["summary"])

        let required = ScreenLayout(visible: ["statistics"], hidden: ["plan"]).updated(for: .today)
        XCTAssertTrue(required.visible.contains("plan"))
        XCTAssertFalse(required.hidden.contains("plan"))
    }

    func testUnreadableStoredLayoutFallsBackToStandard() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ScreenLayoutTests"))
        defaults.removePersistentDomain(forName: "ScreenLayoutTests")
        let store = UserDefaultsScreenLayoutStore(defaults: defaults)

        defaults.set(Data("kaputt".utf8), forKey: UserDefaultsScreenLayoutStore.storageKey(.today))
        XCTAssertNil(store.load(.today))

        try store.save(ScreenLayout(visible: ["goal"], hidden: ["week"]), for: .dashboard)
        XCTAssertEqual(store.load(.dashboard), ScreenLayout(visible: ["goal"], hidden: ["week"]))
        store.remove(.dashboard)
        XCTAssertNil(store.load(.dashboard))
    }
}
