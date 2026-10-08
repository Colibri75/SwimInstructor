import XCTest
@testable import SwimInstructorCore

final class PlanGlanceTests: XCTestCase {
    private let plan = DayPlanV2(rationale: "Test", sessions: [
        DaySession(sport: .bike, sessionType: .endurance, intensity: .easy, focus: "Grundlage", amount: 60, unit: .minutes, distanceMeters: 25_000, durationMinutes: 60, steps: []),
        DaySession(sport: .run, sessionType: .endurance, intensity: .easy, focus: "Koppellauf", amount: 15, unit: .minutes, distanceMeters: 2_500, durationMinutes: 15, brick: true, steps: [])
    ])

    func testTheGlanceListsTheSessionsInPlanOrder() {
        let glance = PlanGlance.make(date: "2026-09-30", todayDone: false, plan: plan, now: TestFixtures.now)

        XCTAssertEqual(glance.items.map(\.title), ["Radfahren · 60 min", "Laufen · 15 min"])
        XCTAssertEqual(glance.items.map(\.focus), ["Grundlage", "Koppellauf"])
        XCTAssertEqual(glance.items.map(\.symbolName), [SportRegistry.standard.symbolName(for: .bike), SportRegistry.standard.symbolName(for: .run)])
        XCTAssertEqual(glance.items.first?.colorRGB, SportRegistry.standard.colorRGB(for: .bike))
    }

    func testWithoutAConcretePlanTheGlanceShowsTheTarget() {
        let session = WeekSession(sport: .swim, sessionType: .technique, intensity: .easy, amount: 2_000, unit: .meters, minutes: 45, distanceMeters: 2_000, focus: "Technik")
        let day = PlannedDay(date: "2026-09-30", content: PlannedDayContent(focus: "Technik", sessions: [session]))

        let glance = PlanGlance.make(day: day, todayDone: false, now: TestFixtures.now)
        XCTAssertEqual(glance.date, "2026-09-30")
        XCTAssertEqual(glance.items.map(\.focus), ["Technik"])
        XCTAssertEqual(glance.items.first?.title, PlanV2Formatting.sessionTitle(sport: .swim, amount: 2_000, unit: .meters))

        let busy = PlannedDay(date: "2026-09-30", content: PlannedDayContent(focus: "Technik", sessions: [session]), isUnavailable: true)
        XCTAssertTrue(PlanGlance.make(day: busy, todayDone: false, now: TestFixtures.now).items.isEmpty, "keine Zeit zeigt sich wie ein Ruhetag")
    }

    func testTheHeadingSaysTodayTomorrowOrNothingWhenStale() {
        let today = PlanGlance.make(date: "2026-09-30", todayDone: false, plan: plan, now: TestFixtures.now)
        let tomorrow = PlanGlance.make(date: "2026-10-01", todayDone: true, plan: plan, now: TestFixtures.now)
        let old = PlanGlance.make(date: "2026-09-28", todayDone: false, plan: plan, now: TestFixtures.now)

        XCTAssertEqual(today.heading(now: TestFixtures.now, calendar: TestFixtures.utc), "Heute")
        XCTAssertEqual(tomorrow.heading(now: TestFixtures.now, calendar: TestFixtures.utc), "Morgen")
        XCTAssertNil(old.heading(now: TestFixtures.now, calendar: TestFixtures.utc))
    }

    func testTheStoreSavesOnlyChangesAndReadsThemBack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plan-glance-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PlanGlanceStore(fileURL: url)
        let glance = PlanGlance.make(date: "2026-09-30", todayDone: false, plan: plan, now: TestFixtures.now)

        XCTAssertNil(store.load())
        XCTAssertTrue(store.save(glance))
        XCTAssertEqual(store.load(), glance)
        XCTAssertFalse(store.save(PlanGlance.make(date: "2026-09-30", todayDone: false, plan: plan, now: Date())), "gleicher Inhalt, nur später")
        XCTAssertTrue(store.save(PlanGlance.make(date: "2026-10-01", todayDone: true, plan: plan, now: Date())))
    }

    func testWithoutAnAppGroupNothingIsReadOrWritten() {
        let store = PlanGlanceStore(fileURL: nil)
        XCTAssertFalse(store.save(PlanGlance(date: "2026-09-30", todayDone: false, items: [], updatedAt: TestFixtures.now)))
        XCTAssertNil(store.load())
    }
}
