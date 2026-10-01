import XCTest
@testable import SwimInstructorCore

final class DailyReminderTests: XCTestCase {
    private let calendar = TestFixtures.utc
    /// 30.09.2026, 12:00 UTC.
    private let now = TestFixtures.now

    private func schedule(hour: Int = 7, minute: Int = 0, enabled: Bool = true) -> ReminderSchedule {
        ReminderSchedule(isEnabled: enabled, hour: hour, minute: minute)
    }

    private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: day > 30 ? 10 : 9, day: day > 30 ? day - 30 : day, hour: hour, minute: minute))!
    }

    // MARK: - Auslösezeitpunkte

    func testFireDatesStartTomorrowWhenTodaysTimeHasPassed() {
        let dates = schedule(hour: 7).upcomingFireDates(from: now, calendar: calendar)

        XCTAssertEqual(dates.count, 6)
        XCTAssertEqual(dates.first, at(day: 31, hour: 7))
        XCTAssertEqual(dates.last, calendar.date(byAdding: .day, value: 5, to: at(day: 31, hour: 7)))
    }

    func testFireDatesIncludeTodayWhenTheTimeIsStillAhead() {
        let dates = schedule(hour: 18, minute: 30).upcomingFireDates(from: now, calendar: calendar)

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(dates.first, at(day: 30, hour: 18, minute: 30))
    }

    func testTheExactCurrentMomentIsNotInTheFuture() {
        let dates = schedule(hour: 12).upcomingFireDates(from: now, calendar: calendar)

        XCTAssertEqual(dates.first, at(day: 31, hour: 12))
    }

    func testDisabledScheduleHasNoDates() {
        XCTAssertTrue(schedule(enabled: false).upcomingFireDates(from: now, calendar: calendar).isEmpty)
        XCTAssertNil(schedule(enabled: false).nextPreparationDate(from: now, calendar: calendar))
    }

    func testDaysCanBeLimited() {
        XCTAssertEqual(schedule().upcomingFireDates(from: now, days: 3, calendar: calendar).count, 2)
        XCTAssertTrue(schedule().upcomingFireDates(from: now, days: 0, calendar: calendar).isEmpty)
    }

    func testInvalidTimeIsClamped() {
        let clamped = ReminderSchedule(isEnabled: true, hour: 27, minute: -5)

        XCTAssertEqual(clamped.hour, 23)
        XCTAssertEqual(clamped.minute, 0)
    }

    // MARK: - Vorbereitung im Hintergrund

    func testPreparationStartsHalfAnHourBeforeTheNextFireDate() {
        let preparation = schedule(hour: 7).nextPreparationDate(from: now, calendar: calendar)

        XCTAssertEqual(preparation, at(day: 31, hour: 6, minute: 30))
    }

    func testPreparationStartsInAMinuteWhenTheLeadWindowHasAlreadyBegun() {
        // 18:20, Auslösung 18:30: Die Vorbereitung hätte um 18:00 beginnen sollen.
        let late = at(day: 30, hour: 18, minute: 20)

        let preparation = schedule(hour: 18, minute: 30).nextPreparationDate(from: late, calendar: calendar)

        XCTAssertEqual(preparation, late.addingTimeInterval(60))
    }

    // MARK: - Speicherung

    @MainActor
    func testSettingsDefaultToOffAtSevenAndSurviveANewInstance() throws {
        let suite = "reminder-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = ReminderSettings(defaults: defaults)
        XCTAssertEqual(first.schedule, ReminderSchedule(isEnabled: false, hour: 7, minute: 0))

        first.schedule = ReminderSchedule(isEnabled: true, hour: 6, minute: 45)

        XCTAssertEqual(ReminderSettings(defaults: defaults).schedule, ReminderSchedule(isEnabled: true, hour: 6, minute: 45))
    }

    @MainActor
    func testCorruptStoredValueFallsBackToDefault() throws {
        let suite = "reminder-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("kaputt".utf8), forKey: ReminderSettings.storageKey)

        XCTAssertEqual(ReminderSettings(defaults: defaults).schedule, .default)
    }

    // MARK: - Text der Benachrichtigung

    func testContentNamesTodaysPlan() {
        let content = ReminderContentBuilder.content(for: TestFixtures.response(), on: now, calendar: calendar)

        XCTAssertEqual(content.title, "Dein Plan für heute")
        XCTAssertEqual(content.body, "Technik, 800 m, locker, rund 25 Minuten")
    }

    func testContentForARestDay() {
        let rest = PlanResponse(
            source: .claude,
            date: "2026-09-30",
            generatedAt: now,
            stale: false,
            plan: TrainingPlan(sessionType: .rest, intensity: .rest, rationale: "Erholung", totalDistanceMeters: 0, estimatedDurationMinutes: 0, sets: [], coachNotes: []),
            adjustments: []
        )

        XCTAssertEqual(ReminderContentBuilder.content(for: rest, on: now, calendar: calendar).title, "Heute ist Ruhetag")
    }

    func testContentWithoutAPlanForThatDayAsksToOpenTheApp() {
        let expected = ReminderContent(
            title: "Dein Trainingsplan für heute",
            body: "Öffne die App, dann erstellt Claude deinen Plan."
        )

        XCTAssertEqual(ReminderContentBuilder.content(for: nil, on: now, calendar: calendar), expected)
        // Der Plan von gestern sagt nichts über heute.
        XCTAssertEqual(
            ReminderContentBuilder.content(for: TestFixtures.response(date: "2026-09-29"), on: now, calendar: calendar),
            expected
        )
        // Und die Benachrichtigung für morgen kennt den heutigen Plan nicht.
        XCTAssertEqual(
            ReminderContentBuilder.content(for: TestFixtures.response(), on: at(day: 31, hour: 7), calendar: calendar),
            expected
        )
    }
}
