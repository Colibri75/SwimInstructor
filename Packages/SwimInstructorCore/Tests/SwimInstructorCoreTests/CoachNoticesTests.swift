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

    func testTheFeedbackQuestionWaitsForARatingOnTheWatch() {
        let end = TestFixtures.now
        XCTAssertEqual(CoachNotices.feedbackDelay(after: end, now: end), 600)
        XCTAssertEqual(CoachNotices.feedbackDelay(after: end, now: end.addingTimeInterval(240)), 360)
        XCTAssertEqual(CoachNotices.feedbackDelay(after: end, now: end.addingTimeInterval(3_600)), 1, "längst vorbei: gleich")
        XCTAssertTrue(CoachNotices.isFeedbackID(CoachNotices.feedbackID(for: UUID())))
        XCTAssertFalse(CoachNotices.isFeedbackID(CoachNotices.morningID(for: "2026-10-01")))
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

    // MARK: - Plan angepasst

    private func plannedDay(_ date: String, _ sessions: [(SportID, Double, PlanIntensity)], extras: [ExtraKind] = []) -> PlannedDay {
        PlannedDay(
            date: date,
            content: PlannedDayContent(focus: "Test", sessions: sessions.map { sport, amount, intensity in
                WeekSession(
                    sport: sport, sessionType: .endurance, intensity: intensity, amount: amount,
                    unit: sport == .swim ? .meters : .minutes, minutes: 40, distanceMeters: 0, focus: "Test"
                )
            }),
            extras: extras.map { WeekExtra(kind: $0, minutes: 20, focus: "Test") }
        )
    }

    func testOnlyNoticeableChangesInTheNextSevenDaysCount() {
        let dates = (1...9).map { String(format: "2026-10-%02d", $0) }
        let before: [PlannedDay?] = [
            plannedDay(dates[0], [(.run, 40, .easy)]),
            plannedDay(dates[1], [(.run, 40, .easy)]),
            plannedDay(dates[2], [(.bike, 60, .easy)]),
            plannedDay(dates[3], []),
            plannedDay(dates[4], [(.swim, 2_000, .easy)]),
            nil,
            plannedDay(dates[6], [(.run, 30, .easy)]),
            plannedDay(dates[7], [(.run, 30, .easy)]),
            plannedDay(dates[8], [(.run, 30, .easy)])
        ]
        let after: [PlannedDay?] = [
            plannedDay(dates[0], [(.run, 43, .easy)]),            // +7 %: nicht spürbar
            plannedDay(dates[1], [(.run, 40, .hard)]),            // andere Intensität
            plannedDay(dates[2], [(.bike, 40, .easy)]),           // ein Drittel weniger
            plannedDay(dates[3], [], extras: [.strength]),        // Kraft dazu
            plannedDay(dates[4], [(.swim, 2_000, .easy)]),        // gleich
            plannedDay(dates[5], [(.run, 30, .easy)]),            // vorher nicht geplant
            plannedDay(dates[6], [(.run, 30, .easy)]),
            plannedDay(dates[7], []),                             // ab Tag 8 zählt nichts mehr
            plannedDay(dates[8], [])
        ]

        let report = PlanChangeReport.make(dates: dates, before: before, after: after, reason: .daily, rationale: "Weil")

        XCTAssertEqual(report.changes.map(\.date), ["2026-10-02", "2026-10-03", "2026-10-04"])
        XCTAssertEqual(report.changes[2].before, "Ruhetag")
        XCTAssertEqual(report.changes[2].after, "Kraft")
        XCTAssertTrue(report.isWorthTelling)
        XCTAssertFalse(PlanChangeReport(reason: .daily, rationale: "", changes: []).isWorthTelling)
        XCTAssertTrue(PlanChangeReport(reason: .pain, rationale: "", changes: []).isWorthTelling, "Beschwerden: immer melden")
    }

    func testThePlanChangedNoticeNamesTheReasonOrTheFirstChangedDay() throws {
        let calendar = WeekCalendar(calendar: TestFixtures.utc)
        let change = PlanChangeReport.DayChange(date: "2026-10-02", before: "Ruhetag", after: "Laufen · 40 min")
        let weekday = calendar.weekdayName("2026-10-02")

        let one = try XCTUnwrap(CoachNotices.planChanged(PlanChangeReport(reason: .daily, rationale: "", changes: [change]), on: "2026-10-01", calendar: calendar))
        XCTAssertEqual(one.id, "plan-changed-2026-10-01")
        XCTAssertEqual(one.title, "Dein Coach hat deinen Plan angepasst")
        XCTAssertEqual(one.body, "\(weekday): jetzt Laufen · 40 min statt Ruhetag.")

        let three = try XCTUnwrap(CoachNotices.planChanged(PlanChangeReport(reason: .daily, rationale: "", changes: [change, change, change]), on: "2026-10-01", calendar: calendar))
        XCTAssertEqual(three.body, "\(weekday): jetzt Laufen · 40 min statt Ruhetag. Dazu 2 weitere Tage.")

        let pain = try XCTUnwrap(CoachNotices.planChanged(PlanChangeReport(reason: .pain, rationale: "", changes: [change]), on: "2026-10-01", calendar: calendar))
        XCTAssertTrue(pain.body.contains("Beschwerden"), pain.body)

        XCTAssertNil(CoachNotices.planChanged(PlanChangeReport(reason: .daily, rationale: "", changes: []), on: "2026-10-01", calendar: calendar))

        let message = CoachNotices.planChangedMessage(
            PlanChangeReport(reason: .daily, rationale: "Mehr Grundlage vor dem Test.", changes: [change]),
            notice: one, at: TestFixtures.now, calendar: calendar
        )
        XCTAssertEqual(message.id, one.id)
        XCTAssertEqual(message.kind, .planChanged)
        XCTAssertEqual(message.details.count, 1)
        XCTAssertTrue(message.details[0].contains("jetzt Laufen · 40 min, vorher Ruhetag"), message.details[0])
        XCTAssertEqual(message.rationale, "Mehr Grundlage vor dem Test.")
    }

    // MARK: - Antippen

    func testEveryNoticeCarriesItsRoute() throws {
        let start = TestFixtures.now
        let end = start.addingTimeInterval(1_800)
        for route in [NotificationRoute.today, .feedback(start: start, end: end), .message(id: "plan-changed-2026-10-01")] {
            XCTAssertEqual(NotificationRoute(identifier: "egal", userInfo: route.userInfo), route)
        }
    }

    func testNoticesFromBeforeRoutesStillLeadSomewhere() {
        let start = TestFixtures.now
        let end = start.addingTimeInterval(1_800)
        let feedbackID = CoachNotices.feedbackID(for: UUID())
        // So kam "Wie war's?" bisher: nur Anfang und Ende der Einheit.
        let old: [AnyHashable: Any] = ["workoutStart": start.timeIntervalSince1970, "workoutEnd": end.timeIntervalSince1970]

        XCTAssertEqual(NotificationRoute(identifier: feedbackID, userInfo: old), .feedback(start: start, end: end))
        XCTAssertEqual(NotificationRoute(identifier: "morning-plan-2026-10-01", userInfo: [:]), .today)
        XCTAssertEqual(NotificationRoute(identifier: "macro-review-2026-09-28", userInfo: [:]), .message(id: "macro-review-2026-09-28"))
        XCTAssertNil(NotificationRoute(identifier: "fremd", userInfo: [:]))
        XCTAssertNil(NotificationRoute(identifier: feedbackID, userInfo: [:]), "ohne Einheit kein Ziel")
    }

    func testPreferencesFromBeforeKeepTheirTimeAndTurnPlanChangesOn() throws {
        let old = Data(#"{"morningPlan":false,"afterWorkout":true,"morningHour":6,"morningMinute":15}"#.utf8)
        let preferences = try JSONDecoder().decode(NotificationPreferences.self, from: old)

        XCTAssertEqual(preferences, NotificationPreferences(morningPlan: false, afterWorkout: true, planChanges: true, morningHour: 6, morningMinute: 15))
    }

    func testTheMessageStoreKeepsTheNewestAndReplacesByID() {
        let defaults = UserDefaults(suiteName: "CoachNoticesTests.messages")!
        defaults.removePersistentDomain(forName: "CoachNoticesTests.messages")
        let store = UserDefaultsCoachMessageStore(defaults: defaults)
        func message(_ id: String, minutes: Double, body: String = "Text") -> CoachMessage {
            CoachMessage(id: id, kind: .planChanged, date: TestFixtures.now.addingTimeInterval(minutes * 60), title: "Titel", body: body)
        }

        store.save(message("a", minutes: 0))
        store.save(message("b", minutes: 1))
        store.save(message("a", minutes: 2, body: "Neu"))

        XCTAssertEqual(store.messages().map(\.id), ["a", "b"])
        XCTAssertEqual(store.message(id: "a")?.body, "Neu")
        for index in 0..<UserDefaultsCoachMessageStore.keep { store.save(message("n\(index)", minutes: Double(10 + index))) }
        XCTAssertEqual(store.messages().count, UserDefaultsCoachMessageStore.keep)
        XCTAssertNil(store.message(id: "b"), "die ältesten fallen heraus")
    }

    func testAMacroReviewMessageHoldsTheWholeReview() {
        let review = MacroReview(
            reviewedAt: TestFixtures.now, weekStart: "2026-09-28", reason: .scheduled, summary: "Du liegst gut im Plan.",
            changes: ["Mehr Rad im Oktober"], adjustments: ["Laufen gedeckelt"], feedback: "Weiter so."
        )
        let message = CoachNotices.macroReviewMessage(review, at: TestFixtures.now)

        XCTAssertEqual(message.id, "macro-review-2026-09-28")
        XCTAssertEqual(message.kind, .macroReview)
        XCTAssertEqual(message.body, "Du liegst gut im Plan.")
        XCTAssertEqual(message.details, ["Mehr Rad im Oktober", "Laufen gedeckelt"])
        XCTAssertEqual(message.rationale, "Weiter so.")
    }
}
