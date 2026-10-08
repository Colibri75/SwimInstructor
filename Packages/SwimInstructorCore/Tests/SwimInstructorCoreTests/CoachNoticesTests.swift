import XCTest
@testable import SwimInstructorCore

final class CoachNoticesTests: XCTestCase {
    private func plan(date: String = "2026-10-01", sessions: [DaySession], extras: [DayExtra] = []) -> DayPlanV2Response {
        DayPlanV2Response(
            source: .claude, date: date, generatedAt: TestFixtures.now, stale: false,
            plan: DayPlanV2(rationale: "Test", sessions: sessions, extras: extras)
        )
    }

    private let run = DaySession(
        sport: .run, sessionType: .endurance, intensity: .easy, focus: "Locker",
        amount: 40, unit: .minutes, distanceMeters: 7_000, durationMinutes: 40, steps: []
    )

    func testTheMorningNoticeNamesTheSessionsAndBlocksOfTheDay() throws {
        let strength = DayExtra(kind: .strength, minutes: 20, focus: "Rumpf", exercises: [])
        let notice = try XCTUnwrap(CoachNotices.morningPlan(plan(sessions: [run], extras: [strength])))

        XCTAssertEqual(notice.id, "morning-plan-2026-10-01")
        XCTAssertEqual(notice.title, "Dein Plan für heute steht")
        XCTAssertEqual(notice.body, "Laufen · 40 min, Kraft")
    }

    func testARestDayGetsNoMorningNotice() {
        XCTAssertNil(CoachNotices.morningPlan(plan(sessions: [])))
    }

    func testTheFeedbackNoticeNamesSportAndDuration() {
        let workout = TestFixtures.workout(.run, daysAgo: 0, minutes: 42)
        let notice = CoachNotices.feedback(for: workout)

        XCTAssertEqual(notice.id, "feedback-\(workout.id.uuidString)")
        XCTAssertEqual(notice.title, "Wie war's?")
        XCTAssertTrue(notice.body.hasPrefix("Laufen, 42 min."), notice.body)
    }

    func testTheMorningNoticeComesAtTheChosenTimeOnlyWhileItIsAhead() throws {
        let preferences = NotificationPreferences(morningHour: 6, morningMinute: 30)
        let fire = try XCTUnwrap(CoachNotices.morningDate(for: "2026-10-01", preferences: preferences, now: TestFixtures.now, calendar: TestFixtures.utc))

        XCTAssertEqual(TestFixtures.utc.dateComponents([.day, .hour, .minute], from: fire), DateComponents(day: 1, hour: 6, minute: 30))
        XCTAssertNil(CoachNotices.morningDate(for: "2026-09-30", preferences: preferences, now: TestFixtures.now, calendar: TestFixtures.utc), "heute 6:30 ist vorbei")
        XCTAssertNil(CoachNotices.morningDate(for: "kein Datum", preferences: preferences, now: TestFixtures.now, calendar: TestFixtures.utc))
    }

    func testPreferencesKeepTheirValuesAndClampTheTime() {
        let defaults = UserDefaults(suiteName: "CoachNoticesTests.preferences")!
        defaults.removePersistentDomain(forName: "CoachNoticesTests.preferences")
        let store = UserDefaultsNotificationPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.preferences(), .standard)
        XCTAssertTrue(store.preferences().morningPlan)
        XCTAssertTrue(store.preferences().afterWorkout)

        store.save(NotificationPreferences(morningPlan: false, afterWorkout: true, morningHour: 30, morningMinute: -5))
        XCTAssertEqual(store.preferences(), NotificationPreferences(morningPlan: false, afterWorkout: true, morningHour: 23, morningMinute: 0))
    }

    func testTheLogRemembersSentNoticesUpToItsLimit() {
        let defaults = UserDefaults(suiteName: "CoachNoticesTests.log")!
        defaults.removePersistentDomain(forName: "CoachNoticesTests.log")
        let log = UserDefaultsNoticeLog(defaults: defaults)

        XCTAssertFalse(log.wasSent("a"))
        log.markSent("a")
        XCTAssertTrue(log.wasSent("a"))

        for index in 0..<UserDefaultsNoticeLog.keep { log.markSent("n\(index)") }
        XCTAssertFalse(log.wasSent("a"), "die ältesten fallen heraus")
        XCTAssertTrue(log.wasSent("n\(UserDefaultsNoticeLog.keep - 1)"))
    }

    func testTheWatchNamesTheEffortInWords() {
        XCTAssertEqual([1, 3, 4, 6, 7, 8, 10].map(SessionFeedback.effortLabel), ["locker", "locker", "mittel", "mittel", "hart", "sehr hart", "sehr hart"])
    }
}
