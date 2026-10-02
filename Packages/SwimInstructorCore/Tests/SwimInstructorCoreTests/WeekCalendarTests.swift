import XCTest
@testable import SwimInstructorCore

final class WeekCalendarTests: XCTestCase {
    private let weekCalendar = WeekCalendar(calendar: TestFixtures.utc)

    func testWeekStartIsTheMondayForEveryDayOfTheWeek() {
        let days = ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"]

        for day in days {
            let date = weekCalendar.date(from: day)!
            XCTAssertEqual(weekCalendar.weekStart(containing: date), "2026-09-28", day)
        }
        XCTAssertEqual(weekCalendar.weekStart(containing: weekCalendar.date(from: "2026-10-05")!), "2026-10-05")
        XCTAssertEqual(weekCalendar.weekStart(containing: weekCalendar.date(from: "2026-09-27")!), "2026-09-21")
    }

    func testWeekStartCrossesMonthAndYearBoundaries() {
        XCTAssertEqual(weekCalendar.weekStart(containing: weekCalendar.date(from: "2027-01-01")!), "2026-12-28")
        XCTAssertEqual(weekCalendar.weekStart(containing: weekCalendar.date(from: "2026-03-01")!), "2026-02-23")
    }

    func testWeekRunsFromMondayEvenWithAnAmericanCalendar() {
        var american = TestFixtures.utc
        american.firstWeekday = 1
        let calendar = WeekCalendar(calendar: american)

        XCTAssertEqual(calendar.weekStart(containing: calendar.date(from: "2026-10-04")!), "2026-09-28")
    }

    func testDatesOfAWeekAreSevenDaysFromMonday() {
        XCTAssertEqual(
            weekCalendar.dates(inWeekStarting: "2026-09-28"),
            ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"]
        )
        XCTAssertEqual(weekCalendar.dates(inWeekStarting: "kaputt"), [])
    }

    func testAddingDaysAcrossBoundaries() {
        XCTAssertEqual(weekCalendar.addingDays(1, to: "2026-09-30"), "2026-10-01")
        XCTAssertEqual(weekCalendar.addingDays(-7, to: "2026-09-28"), "2026-09-21")
        XCTAssertEqual(weekCalendar.addingDays(7, to: "2026-12-28"), "2027-01-04")
        XCTAssertNil(weekCalendar.addingDays(1, to: "morgen"))
    }

    func testWeekdayNamesAreGerman() {
        XCTAssertEqual(weekCalendar.weekdayShort("2026-09-28"), "Mo")
        XCTAssertEqual(weekCalendar.weekdayShort("2026-10-04"), "So")
        XCTAssertEqual(weekCalendar.weekdayName("2026-09-30"), "Mittwoch")
        XCTAssertEqual(weekCalendar.weekdayName("2026-10-03"), "Samstag")
        XCTAssertEqual(weekCalendar.weekdayName("kaputt"), "kaputt")
    }

    func testKeyAndDateRoundTrip() {
        XCTAssertEqual(weekCalendar.key(for: weekCalendar.date(from: "2026-10-01")!), "2026-10-01")
        XCTAssertNil(weekCalendar.date(from: "2026-10"))
    }

    func testShortGermanDate() {
        XCTAssertEqual(PlanFormatting.shortGermanDate("2026-09-30"), "30.09.")
        XCTAssertEqual(PlanFormatting.shortGermanDate("kaputt"), "kaputt")
    }

    func testDatesFromADayCrossWeeksAndMonths() {
        let calendar = WeekCalendar(calendar: TestFixtures.utc)

        XCTAssertEqual(calendar.dates(from: "2026-09-30", count: 7), ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06"])
        XCTAssertEqual(calendar.dates(from: "2026-09-30", count: 1), ["2026-09-30"])
        XCTAssertEqual(calendar.dates(from: "2026-09-30", count: 0), [])
        XCTAssertEqual(calendar.dates(from: "kein Datum", count: 3), [])
    }
}

