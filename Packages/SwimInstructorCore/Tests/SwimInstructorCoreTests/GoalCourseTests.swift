import XCTest
@testable import SwimInstructorCore

/// "Bin ich auf Kurs?" Heute ist Mittwoch, der 30.09.2026 (TestFixtures.now), die laufende Woche beginnt am 28.09.
final class GoalCourseTests: XCTestCase {
    private let evaluator = GoalCourseEvaluator(registry: TestFixtures.triathlon, calendar: TestFixtures.utc)

    /// Je Woche: Schwimmen 4000 m (80 min, 2 Einheiten), Rad 120 min (2), Laufen 90 min (3).
    private func week(_ start: String) -> MacroWeekV2 {
        MacroWeekV2(
            weekStart: start, phase: .base, deload: false, focus: "Grundlage", totalMinutes: 290, load: 290,
            sports: [
                MacroSportVolume(sport: .swim, unit: .meters, amount: 4_000, minutes: 80, distanceMeters: 4_000, sessions: 2),
                MacroSportVolume(sport: .bike, unit: .minutes, amount: 120, minutes: 120, distanceMeters: 50_000, sessions: 2),
                MacroSportVolume(sport: .run, unit: .minutes, amount: 90, minutes: 90, distanceMeters: 15_000, sessions: 3)
            ]
        )
    }

    /// Erstellt in der Woche ab 31.08. (zählt nicht), dann 07.09., 14.09., 21.09. abgeschlossen, 28.09. läuft, 05.10. kommt.
    private func plan(generatedDaysAgo: Int = 30) -> MacroPlanV2 {
        MacroPlanV2(
            goalKey: "test", goalDay: "2026-10-11", generatedAt: TestFixtures.date(daysAgo: generatedDaysAgo, hour: 8),
            rationale: "",
            weeks: ["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05"].map(week)
        )
    }

    private func workout(_ sport: SportID, daysAgo: Int, minutes: Double, meters: Double? = nil) -> Workout {
        let start = TestFixtures.date(daysAgo: daysAgo, hour: 8)
        return Workout(
            id: UUID(), sport: sport, startDate: start, endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60, distanceMeters: meters
        )
    }

    /// Eine Woche wie geplant; `mondayDaysAgo` ist der Montag der Woche, `factor` streckt alles.
    private func plannedWeek(mondayDaysAgo: Int, factor: Double = 1, run: Bool = true) -> [Workout] {
        var workouts = [
            workout(.swim, daysAgo: mondayDaysAgo, minutes: 40 * factor, meters: 2_000 * factor),
            workout(.swim, daysAgo: mondayDaysAgo - 2, minutes: 40 * factor, meters: 2_000 * factor),
            workout(.bike, daysAgo: mondayDaysAgo - 1, minutes: 60 * factor),
            workout(.bike, daysAgo: mondayDaysAgo - 5, minutes: 60 * factor)
        ]
        if run {
            workouts += [0, 3, 6].map { workout(.run, daysAgo: mondayDaysAgo - $0, minutes: 30 * factor) }
        }
        return workouts
    }

    /// Montage der abgeschlossenen Wochen: 07.09. = 23 Tage her, 14.09. = 16, 21.09. = 9.
    private let mondays = [23, 16, 9]

    func testEverythingAsPlannedIsOnTrack() {
        let workouts = mondays.flatMap { plannedWeek(mondayDaysAgo: $0) }
        let course = evaluator.evaluate(plan: plan(), workouts: workouts, now: TestFixtures.now)

        XCTAssertEqual(course.status, .onTrack)
        XCTAssertEqual(course.percent, 100)
        XCTAssertEqual(course.weekStarts, ["2026-09-07", "2026-09-14", "2026-09-21"], "Erstellungswoche und laufende Woche zählen nicht")
        XCTAssertEqual(course.sports.map(\.sport), [.swim, .bike, .run])
        XCTAssertEqual(course.sports.first?.planned, 12_000)
        XCTAssertEqual(course.sports.first?.done, 12_000)
        XCTAssertEqual(course.plannedSessions, 21)
        XCTAssertEqual(course.doneSessions, 21)
        XCTAssertEqual(course.sentence(registry: TestFixtures.triathlon), "In den letzten 3 Wochen hast du 100 % vom Plan trainiert. Mach so weiter.")
    }

    func testASportFarBelowThePlanMeansTrainMore() {
        let workouts = mondays.flatMap { plannedWeek(mondayDaysAgo: $0, run: false) }
        let course = evaluator.evaluate(plan: plan(), workouts: workouts, now: TestFixtures.now)

        XCTAssertEqual(course.status, .trainMore)
        XCTAssertEqual(course.sports.first { $0.sport == .run }?.percent, 0)
        XCTAssertEqual(course.lowSports, [.run])
        // Schwimmen und Rad 100 %, Laufen 0 %, nach Minuten gewichtet: 200 von 290.
        XCTAssertEqual(course.percent, 69)
    }

    func testMuchMoreThanPlannedMeansTrainLess() {
        let workouts = mondays.flatMap { plannedWeek(mondayDaysAgo: $0, factor: 1.4) }
        let course = evaluator.evaluate(plan: plan(), workouts: workouts, now: TestFixtures.now)

        XCTAssertEqual(course.status, .trainLess)
        XCTAssertEqual(course.percent, 140)
    }

    func testExtraVolumeInOneSportCannotHideAMissingOne() {
        // Rad dreifach, Laufen gar nicht: Rad zählt höchstens mit 150 %.
        let workouts = mondays.flatMap { monday -> [Workout] in
            plannedWeek(mondayDaysAgo: monday, run: false) + [workout(.bike, daysAgo: monday - 3, minutes: 240)]
        }
        let course = evaluator.evaluate(plan: plan(), workouts: workouts, now: TestFixtures.now)

        XCTAssertEqual(course.status, .trainMore)
        XCTAssertEqual(course.sports.first { $0.sport == .bike }?.percent, 300)
    }

    func testAPlanFromThisWeekHasNoDataYet() {
        let course = evaluator.evaluate(plan: plan(generatedDaysAgo: 1), workouts: [], now: TestFixtures.now)

        XCTAssertEqual(course.status, .noData)
        XCTAssertNil(course.percent)
        XCTAssertEqual(course.sentence(registry: TestFixtures.triathlon), "Nach der ersten vollen Woche mit Plan siehst du hier, ob du auf Kurs bist.")
    }

    func testAWeekWithAReportedPauseDoesNotCount() {
        // In der Woche ab 21.09. krank, nichts trainiert.
        let workouts = [23, 16].flatMap { plannedWeek(mondayDaysAgo: $0) }
        let pause = PauseReport(kind: .sick, from: "2026-09-21", to: "2026-09-25", reportedAt: TestFixtures.now)
        let course = evaluator.evaluate(plan: plan(), workouts: workouts, now: TestFixtures.now, pause: pause)

        XCTAssertEqual(course.weekStarts, ["2026-09-07", "2026-09-14"])
        XCTAssertEqual(course.status, .onTrack)
    }

    func testOnlyTheLastFourWeeksCount() {
        let longPlan = MacroPlanV2(
            goalKey: "test", goalDay: "2026-10-11", generatedAt: TestFixtures.date(daysAgo: 60, hour: 8), rationale: "",
            weeks: ["2026-07-27", "2026-08-03", "2026-08-10", "2026-08-17", "2026-08-24", "2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28"].map(week)
        )
        let course = evaluator.evaluate(plan: longPlan, workouts: [], now: TestFixtures.now)

        XCTAssertEqual(course.weekStarts, ["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21"])
        XCTAssertEqual(course.status, .trainMore)
        XCTAssertEqual(course.sentence(registry: TestFixtures.triathlon), "In den letzten 4 Wochen hast du 0 % vom Plan trainiert. Versuch, die geplanten Einheiten zu schaffen, vor allem bei Schwimmen, Radfahren und Laufen.")
    }

    func testTheLineHasEveryWeekAndStopsAtThisWeek() {
        let workouts = plannedWeek(mondayDaysAgo: 9) + [workout(.run, daysAgo: 1, minutes: 45)]
        let course = evaluator.evaluate(plan: plan(), workouts: workouts, now: TestFixtures.now)

        XCTAssertEqual(course.weeks.map(\.weekStart), ["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05"])
        XCTAssertEqual(course.weeks.map(\.plannedMinutes), Array(repeating: 290, count: 6))
        XCTAssertEqual(course.weeks[3].doneMinutes, 290)
        XCTAssertEqual(course.weeks[4].doneMinutes, 45)
        XCTAssertTrue(course.weeks[4].isCurrent)
        XCTAssertNil(course.weeks[5].doneMinutes, "kommende Woche ohne Ist")
    }

    func testWeeksBeforeTheReadHealthDataHaveNoActual() {
        // Einheiten liegen ab Mittwoch, 09.09., vor: Die Woche ab 07.09. ist nur zum Teil gelesen.
        let workouts = [16, 9].flatMap { plannedWeek(mondayDaysAgo: $0) }
        let course = evaluator.evaluate(plan: plan(), workouts: workouts, now: TestFixtures.now, historyStart: TestFixtures.date(daysAgo: 21, hour: 0))

        XCTAssertNil(course.weeks[1].doneMinutes)
        XCTAssertEqual(course.weeks[2].doneMinutes, 290)
        XCTAssertEqual(course.weekStarts, ["2026-09-14", "2026-09-21"])
        XCTAssertEqual(course.status, .onTrack)
        XCTAssertEqual(course.sentence(registry: TestFixtures.triathlon), "In den letzten 2 Wochen hast du 100 % vom Plan trainiert. Mach so weiter.")
    }
}
