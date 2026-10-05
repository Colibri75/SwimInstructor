import XCTest
@testable import SwimInstructorCore

final class WeeklyScheduleTests: XCTestCase {
    private func goal(days: Int = 5, hours: Double = 7.5) -> TrainingGoal {
        GoalTemplate.template(id: "triathlon_olympic")!
            .goal(targetDate: TestFixtures.now.addingTimeInterval(120 * 86_400), trainingDaysPerWeek: days, weeklyHours: hours)
    }

    func testFromDaysAndHoursUsesTheFixedPatternAndRoundsToQuarterHours() {
        let three = WeeklySchedule(trainingDaysPerWeek: 3, weeklyHours: 5)
        XCTAssertEqual(three.days.filter(\.trains).map(\.weekday), [2, 4, 6])
        // 100 min je Tag, auf 15 gerundet: 105.
        XCTAssertEqual(three.days.filter(\.trains).map(\.maxMinutes), [105, 105, 105])
        XCTAssertEqual(three.days.filter { !$0.trains }.map(\.maxMinutes), [0, 0, 0, 0])
        XCTAssertNil(three.problem())

        XCTAssertEqual(WeeklySchedule(trainingDaysPerWeek: 1, weeklyHours: 1).days.filter(\.trains).map(\.weekday), [6])
        XCTAssertEqual(WeeklySchedule(trainingDaysPerWeek: 5, weeklyHours: 6).days.filter(\.trains).map(\.weekday), [2, 3, 4, 6, 7])
        XCTAssertEqual(WeeklySchedule(trainingDaysPerWeek: 9, weeklyHours: 1).trainingDays, 7)
        // Unter 15 min je Tag wird auf 15 angehoben.
        XCTAssertEqual(WeeklySchedule(trainingDaysPerWeek: 7, weeklyHours: 1).days.map(\.maxMinutes), Array(repeating: 15, count: 7))
    }

    func testAppliedGoalTakesDaysAndHoursFromTheSchedule() {
        let schedule = WeeklySchedule(trainingDaysPerWeek: 4, weeklyHours: 6)
            .setting(.init(weekday: 6, trains: true, timeOfDay: .morning, maxMinutes: 140))
        // 90 + 90 + 135 (140 auf 15 gerundet) + 90 = 405 min = 6,75 h.
        XCTAssertEqual(schedule.totalMinutes, 405)
        let applied = schedule.applied(to: goal())
        XCTAssertEqual(applied.trainingDaysPerWeek, 4)
        XCTAssertEqual(applied.weeklyHours, 6.75)
        XCTAssertEqual(applied.disciplines, goal().disciplines)
        XCTAssertNil(applied.problem())

        // Unter einer Stunde bleibt das Ziel gültig.
        let short = WeeklySchedule(trainingDaysPerWeek: 1, weeklyHours: 0.25)
        XCTAssertEqual(short.applied(to: goal()).weeklyHours, 1)
    }

    func testRestDayLosesTimeAndSport() {
        let schedule = WeeklySchedule(trainingDaysPerWeek: 3, weeklyHours: 3)
            .setting(.init(weekday: 2, trains: false, timeOfDay: .evening, maxMinutes: 60, sport: .swim))
        XCTAssertEqual(schedule.day(2), .init(weekday: 2, trains: false, maxMinutes: 0))
        XCTAssertEqual(schedule.trainingDays, 2)
        XCTAssertEqual(schedule.summary, "2 Tage, 2 h")
        XCTAssertEqual(WeeklySchedule(trainingDaysPerWeek: 1, weeklyHours: 1.25).summary, "1 Tag, 1 h 15 min")
    }

    func testProblems() {
        var schedule = WeeklySchedule(trainingDaysPerWeek: 3, weeklyHours: 3)
        XCTAssertNil(schedule.problem())

        var noDays = schedule
        noDays.days = noDays.days.map { WeeklySchedule.Day(weekday: $0.weekday, trains: false, maxMinutes: 0) }
        XCTAssertEqual(noDays.problem(), "Mindestens ein Tag mit Training.")

        var missing = schedule
        missing.days.removeLast()
        XCTAssertEqual(missing.problem(), "Der Wochenraster braucht jeden Wochentag genau einmal.")

        schedule.days[1].maxMinutes = 10
        XCTAssertEqual(schedule.problem(), "Dienstag: 15 bis 600 Minuten.")
        schedule.days[1].maxMinutes = 60
        schedule.days[1].sport = "kayak"
        XCTAssertEqual(schedule.problem(), "Dienstag: unbekannte Sportart.")
    }

    func testStoreKeepsOnlyValidSchedulesAndFallsBackToTheGoal() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WeeklyScheduleTests-\(UUID().uuidString)"))
        let store = UserDefaultsWeeklyScheduleStore(defaults: defaults)
        XCTAssertNil(store.storedSchedule())
        XCTAssertEqual(store.schedule(for: goal(days: 3, hours: 4.5)), WeeklySchedule(trainingDaysPerWeek: 3, weeklyHours: 4.5))

        let schedule = WeeklySchedule(trainingDaysPerWeek: 4, weeklyHours: 6)
            .setting(.init(weekday: 2, trains: true, timeOfDay: .evening, maxMinutes: 60, sport: .swim))
        XCTAssertTrue(store.setSchedule(schedule))
        XCTAssertEqual(store.storedSchedule(), schedule)
        XCTAssertEqual(store.schedule(for: goal()), schedule)

        var broken = schedule
        broken.days.removeAll()
        XCTAssertFalse(store.setSchedule(broken))
        XCTAssertEqual(store.storedSchedule(), schedule)
    }

    func testDayOnADateUsesItsWeekday() {
        let schedule = WeeklySchedule(trainingDaysPerWeek: 3, weeklyHours: 5)
        let calendar = WeekCalendar(calendar: TestFixtures.utc)
        // 06.10.2026 ist ein Dienstag, 11.10.2026 ein Sonntag.
        XCTAssertEqual(schedule.day(on: "2026-10-06", weekCalendar: calendar)?.weekday, 2)
        XCTAssertEqual(schedule.day(on: "2026-10-06", weekCalendar: calendar)?.trains, true)
        XCTAssertEqual(schedule.day(on: "2026-10-11", weekCalendar: calendar)?.weekday, 7)
        XCTAssertEqual(schedule.day(on: "2026-10-11", weekCalendar: calendar)?.trains, false)
        XCTAssertNil(schedule.day(on: "kein Datum", weekCalendar: calendar))
    }
}
