import XCTest
@testable import SwimInstructorCore

/// Bausteine für "Plan gegen Ist" in Plan v2. "Heute" ist Mittwoch, der 30.09.2026, 12 Uhr (TestFixtures.now).
private enum ProgressV2Data {
    static func day(_ daysAgo: Int) -> String {
        PlanFormatting.isoDay(TestFixtures.date(daysAgo: daysAgo, hour: 12), calendar: TestFixtures.utc)
    }

    /// Schwimmen in Metern, Rad und Laufen in Minuten.
    static func unit(of sport: SportID) -> PlanUnit {
        sport == SportID.swim ? PlanUnit.meters : PlanUnit.minutes
    }

    static func planned(_ sport: SportID, _ amount: Double, minutes: Double) -> MultiSportComparator.Planned {
        MultiSportComparator.Planned(sport: sport, unit: unit(of: sport), amount: amount, minutes: minutes)
    }

    static func workout(_ sport: SportID, daysAgo: Int, minutes: Double, meters: Double? = nil, hour: Int = 8) -> Workout {
        let start = TestFixtures.date(daysAgo: daysAgo, hour: hour)
        return Workout(
            id: UUID(), sport: sport, startDate: start, endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60, distanceMeters: meters
        )
    }

    static func session(_ sport: SportID, _ amount: Double, minutes: Double) -> WeekSession {
        WeekSession(
            sport: sport, sessionType: .endurance, intensity: .easy, amount: amount, unit: unit(of: sport),
            minutes: minutes, distanceMeters: sport == SportID.swim ? amount : minutes * 60 * 3, focus: "Grundlage"
        )
    }

    static func plannedDay(_ date: String, _ sessions: [WeekSession]) -> PlannedDay {
        PlannedDay(date: date, content: PlannedDayContent(focus: sessions.isEmpty ? "Ruhetag" : "Training", sessions: sessions))
    }

    static func week(_ days: [PlannedDay]) -> WeekPlanV2 {
        WeekPlanV2(weekStart: "2026-09-28", generatedAt: TestFixtures.now, rationale: "Test", days: days)
    }

    static func daySession(_ sport: SportID, _ amount: Double, minutes: Double) -> DaySession {
        DaySession(
            sport: sport, sessionType: .endurance, intensity: .easy, focus: "Grundlage",
            amount: amount, unit: unit(of: sport), distanceMeters: sport == SportID.swim ? amount : minutes * 60 * 3,
            durationMinutes: minutes, steps: []
        )
    }

    static func dayPlan(daysAgo: Int, _ sessions: [DaySession]) -> DayPlanV2Response {
        DayPlanV2Response(
            source: .claude, date: day(daysAgo), generatedAt: TestFixtures.now, stale: false,
            plan: DayPlanV2(rationale: "Test", sessions: sessions)
        )
    }
}

final class MultiSportProgressTests: XCTestCase {
    private let comparator = MultiSportComparator(registry: SportRegistry.standard)
    private let adherence = MultiSportAdherenceCalculator(calendar: TestFixtures.utc)
    private let weekProgress = MultiSportWeekProgressCalculator(calendar: TestFixtures.utc)

    private func outcome(
        _ planned: [MultiSportComparator.Planned],
        _ workouts: [Workout],
        isToday: Bool = false
    ) -> AdherenceOutcome {
        let comparisons = comparator.compare(planned: planned, workouts: workouts)
        return comparator.outcome(of: comparisons, isRestDay: planned.isEmpty, isToday: isToday)
    }

    /// Gestern geschwommen, so viele Meter in 40 Minuten.
    private func swum(_ meters: Double) -> [Workout] {
        [ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 40, meters: meters)]
    }

    private func statuses(_ plan: WeekPlanV2?, _ workouts: [Workout] = []) -> [MultiSportDayStatus] {
        weekProgress.statuses(plan: plan, weekStart: "2026-09-28", workouts: workouts, now: TestFixtures.now)
    }

    private func state(_ date: String, _ plan: WeekPlanV2?, _ workouts: [Workout] = []) -> WeekDayState? {
        statuses(plan, workouts).first(where: { $0.date == date })?.state
    }

    // MARK: - Vergleich je Sportart

    func testPlannedSportsComeFirstThenTheOtherSportsInRegistryOrder() {
        let comparisons = comparator.compare(
            planned: [ProgressV2Data.planned(.run, 40, minutes: 40)],
            workouts: [
                ProgressV2Data.workout(.bike, daysAgo: 1, minutes: 60, meters: 25_000),
                ProgressV2Data.workout(.run, daysAgo: 1, minutes: 42, meters: 7_000),
                ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 30, meters: 1_200),
                // Eine Sportart, die die App nicht kennt, zählt nicht.
                ProgressV2Data.workout(SportID(rawValue: "kayak"), daysAgo: 1, minutes: 45)
            ]
        )

        XCTAssertEqual(comparisons.map(\.sport), [SportID.run, SportID.swim, SportID.bike])
        XCTAssertEqual(comparisons.map(\.isPlanned), [true, false, false])
        XCTAssertEqual(comparisons.map(\.unit), [PlanUnit.minutes, PlanUnit.meters, PlanUnit.minutes])
        XCTAssertEqual(comparisons.map(\.workoutCount), [1, 1, 1])
    }

    func testSwimIsComparedInMetersAndBikeAndRunInMinutes() throws {
        let comparisons = comparator.compare(
            planned: [
                ProgressV2Data.planned(.swim, 2_000, minutes: 40),
                ProgressV2Data.planned(.bike, 60, minutes: 60),
                ProgressV2Data.planned(.run, 30, minutes: 30)
            ],
            workouts: [
                ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 20, meters: 1_000, hour: 7),
                ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 16, meters: 800, hour: 18),
                ProgressV2Data.workout(.bike, daysAgo: 1, minutes: 75, meters: 30_000, hour: 9),
                ProgressV2Data.workout(.run, daysAgo: 1, minutes: 25, meters: 4_500, hour: 12)
            ]
        )

        XCTAssertEqual(comparisons, [
            SportComparison(sport: .swim, unit: .meters, planned: 2_000, actual: 1_800, plannedSessions: 1, workoutCount: 2, plannedMinutes: 40, actualMinutes: 36),
            SportComparison(sport: .bike, unit: .minutes, planned: 60, actual: 75, plannedSessions: 1, workoutCount: 1, plannedMinutes: 60, actualMinutes: 75),
            SportComparison(sport: .run, unit: .minutes, planned: 30, actual: 25, plannedSessions: 1, workoutCount: 1, plannedMinutes: 30, actualMinutes: 25)
        ])
        let swim = try XCTUnwrap(comparisons.first)
        XCTAssertEqual(swim.id, SportID.swim)
    }

    func testSwimWithoutDistanceIsEstimatedFromItsDuration() throws {
        // 30 Minuten mit dem typischen Tempo von 0,8 m/s: 1440 m.
        let planned = comparator.compare(
            planned: [ProgressV2Data.planned(.swim, 1_500, minutes: 30)],
            workouts: [ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 30)]
        )
        let swim = try XCTUnwrap(planned.first)
        XCTAssertEqual(swim.actual, 1_440, accuracy: 0.001)
        XCTAssertEqual(swim.actualMinutes, 30, accuracy: 0.001)

        // Auch ohne Plan zählt das Schwimmen in Metern.
        let unplanned = try XCTUnwrap(comparator.compare(planned: [], workouts: [ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 30)]).first)
        XCTAssertEqual(unplanned.unit, PlanUnit.meters)
        XCTAssertEqual(unplanned.actual, 1_440, accuracy: 0.001)
        XCTAssertFalse(unplanned.isPlanned)
    }

    func testTwoSessionsOfOneSportAreAdded() throws {
        let comparisons = comparator.compare(
            planned: [ProgressV2Data.planned(.run, 30, minutes: 30), ProgressV2Data.planned(.run, 20, minutes: 20)],
            workouts: [ProgressV2Data.workout(.run, daysAgo: 1, minutes: 45, meters: 8_000)]
        )

        let run = try XCTUnwrap(comparisons.first)
        XCTAssertEqual(comparisons.count, 1)
        XCTAssertEqual(run.planned, 50)
        XCTAssertEqual(run.plannedSessions, 2)
        XCTAssertEqual(run.plannedMinutes, 50)
        XCTAssertEqual(run.actual, 45)
    }

    func testAPlannedSportTheAppDoesNotKnowStaysInTheComparison() throws {
        let kayak = SportID(rawValue: "kayak")
        let comparisons = comparator.compare(
            planned: [MultiSportComparator.Planned(sport: kayak, unit: .minutes, amount: 30, minutes: 30)],
            workouts: [ProgressV2Data.workout(kayak, daysAgo: 1, minutes: 30)]
        )

        let entry = try XCTUnwrap(comparisons.first)
        XCTAssertEqual(comparisons.map(\.sport), [kayak])
        XCTAssertEqual(entry.planned, 30)
        // Ihre Einheiten zählen nicht.
        XCTAssertEqual(entry.workoutCount, 0)
    }

    // MARK: - Wie der Tag ausging

    func testARestDayIsKeptBrokenOrStillOpenToday() {
        XCTAssertEqual(outcome([], []), .restKept)
        XCTAssertEqual(outcome([], [], isToday: true), .pending)
        XCTAssertEqual(outcome([], [ProgressV2Data.workout(.bike, daysAgo: 1, minutes: 30)]), .restBroken)
        XCTAssertEqual(outcome([], [ProgressV2Data.workout(.run, daysAgo: 0, minutes: 20)], isToday: true), .restBroken)
    }

    func testATrainingDayWithoutAnyWorkoutIsMissedOrStillOpenToday() {
        let swim = [ProgressV2Data.planned(.swim, 2_000, minutes: 40)]

        XCTAssertEqual(outcome(swim, []), .missed)
        XCTAssertEqual(outcome(swim, [], isToday: true), .pending)
        // Einheiten unbekannter Sportarten zählen nicht.
        XCTAssertEqual(outcome(swim, [ProgressV2Data.workout(SportID(rawValue: "kayak"), daysAgo: 1, minutes: 40)]), .missed)
    }

    func testTheToleranceBandRunsFrom75To125Percent() {
        let swim = [ProgressV2Data.planned(.swim, 2_000, minutes: 40)]

        XCTAssertEqual(MultiSportComparator.lowerTolerance, 0.75)
        XCTAssertEqual(MultiSportComparator.upperTolerance, 1.25)
        XCTAssertEqual(outcome(swim, swum(1_500)), .followed)
        XCTAssertEqual(outcome(swim, swum(1_490)), .shorter)
        XCTAssertEqual(outcome(swim, swum(2_500)), .followed)
        XCTAssertEqual(outcome(swim, swum(2_510)), .longer)
    }

    func testTodayATooShortDayStaysOpen() {
        let swim = [ProgressV2Data.planned(.swim, 2_000, minutes: 40)]

        // Heute kann noch etwas folgen: zu kurz bleibt offen, passend oder zu lang steht fest.
        XCTAssertEqual(outcome(swim, swum(1_000), isToday: true), .pending)
        XCTAssertEqual(outcome(swim, swum(2_000), isToday: true), .followed)
        XCTAssertEqual(outcome(swim, swum(2_600), isToday: true), .longer)
    }

    func testATrainingDayIsDoneWhenEveryPlannedSportHasItsSessions() {
        let planned = [ProgressV2Data.planned(.swim, 2_000, minutes: 40), ProgressV2Data.planned(.run, 30, minutes: 30)]
        func done(_ planned: [MultiSportComparator.Planned], _ workouts: [Workout]) -> Bool {
            MultiSportDayStatus(date: "2026-09-29", day: nil, comparisons: comparator.compare(planned: planned, workouts: workouts), state: .today).isTrainingDone
        }
        let swim = ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 40, meters: 2_000)
        let run = ProgressV2Data.workout(.run, daysAgo: 1, minutes: 30, meters: 5_000)

        XCTAssertFalse(done(planned, []))
        // Schwimmen gemacht, der Lauf fehlt noch.
        XCTAssertFalse(done(planned, [swim]))
        XCTAssertTrue(done(planned, [swim, run]))
        // Ein Ruhetag ist nie erledigt, auch nicht mit Training.
        XCTAssertFalse(done([], [run]))
    }

    func testBikeAndRunCountTheirMinutes() {
        let bike = [ProgressV2Data.planned(.bike, 60, minutes: 60)]

        // Die Strecke spielt beim Rad keine Rolle.
        XCTAssertEqual(outcome(bike, [ProgressV2Data.workout(.bike, daysAgo: 1, minutes: 44, meters: 40_000)]), .shorter)
        XCTAssertEqual(outcome(bike, [ProgressV2Data.workout(.bike, daysAgo: 1, minutes: 46, meters: 10_000)]), .followed)
        XCTAssertEqual(outcome(bike, [ProgressV2Data.workout(.bike, daysAgo: 1, minutes: 80)]), .longer)
    }

    func testADifferentSportInsteadOfThePlannedOneCountsWithItsMinutes() {
        let run = [ProgressV2Data.planned(.run, 60, minutes: 60)]

        XCTAssertEqual(outcome(run, [ProgressV2Data.workout(.bike, daysAgo: 1, minutes: 60, meters: 25_000)]), .followed)
        // 1500 m in 30 Minuten statt 60 Minuten Laufen: zählt mit 30 Minuten.
        XCTAssertEqual(outcome(run, [ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 30, meters: 1_500)]), .shorter)
        XCTAssertEqual(outcome(run, [ProgressV2Data.workout(.bike, daysAgo: 1, minutes: 90)]), .longer)
    }

    func testEverySportOfTheDayCountsWithItsShareOfThePlannedMinutes() {
        let planned = [ProgressV2Data.planned(.swim, 1_500, minutes: 30), ProgressV2Data.planned(.run, 30, minutes: 30)]
        let swimOnly = [ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 30, meters: 1_500, hour: 7)]
        let both = swimOnly + [ProgressV2Data.workout(.run, daysAgo: 1, minutes: 28, meters: 5_000, hour: 18)]

        // Nur geschwommen: 30 von 60 Minuten.
        XCTAssertEqual(outcome(planned, swimOnly), .shorter)
        XCTAssertEqual(outcome(planned, both), .followed)
    }

    func testWithoutPlannedMinutesAnyWorkoutCountsAsFollowed() {
        let planned = [ProgressV2Data.planned(.swim, 1_000, minutes: 0)]

        XCTAssertEqual(outcome(planned, [ProgressV2Data.workout(.swim, daysAgo: 1, minutes: 10, meters: 300)]), .followed)
    }

    // MARK: - Verlauf der Tagespläne

    func testAdherenceEntriesCompareEveryStoredDayPlanNewestFirst() throws {
        let plans = [
            ProgressV2Data.dayPlan(daysAgo: 40, [ProgressV2Data.daySession(.swim, 1_500, minutes: 30)]),   // zu alt
            ProgressV2Data.dayPlan(daysAgo: 3, [
                ProgressV2Data.daySession(.swim, 1_500, minutes: 30),
                ProgressV2Data.daySession(.run, 30, minutes: 30)
            ]),
            ProgressV2Data.dayPlan(daysAgo: 2, [ProgressV2Data.daySession(.bike, 60, minutes: 60)]),         // verpasst
            ProgressV2Data.dayPlan(daysAgo: 1, []),                                                        // Ruhetag
            ProgressV2Data.dayPlan(daysAgo: 0, [ProgressV2Data.daySession(.run, 40, minutes: 40)]),          // heute
            ProgressV2Data.dayPlan(daysAgo: -1, [ProgressV2Data.daySession(.swim, 1_500, minutes: 30)])    // morgen
        ]
        let workouts = [
            ProgressV2Data.workout(.swim, daysAgo: 3, minutes: 30, meters: 1_500, hour: 7),
            ProgressV2Data.workout(.run, daysAgo: 3, minutes: 32, meters: 5_500, hour: 18),
            // Heute Abend, noch nicht geschehen.
            ProgressV2Data.workout(.run, daysAgo: 0, minutes: 40, meters: 7_000, hour: 20)
        ]

        let entries = adherence.entries(plans: plans, workouts: workouts, now: TestFixtures.now)

        XCTAssertEqual(entries.map(\.date), [ProgressV2Data.day(0), ProgressV2Data.day(1), ProgressV2Data.day(2), ProgressV2Data.day(3)])
        XCTAssertEqual(entries.map(\.outcome), [.pending, .restKept, .missed, .followed])
        let both = try XCTUnwrap(entries.last)
        XCTAssertEqual(both.id, ProgressV2Data.day(3))
        XCTAssertEqual(both.comparisons.map(\.sport), [SportID.swim, SportID.run])
        XCTAssertEqual(both.comparisons.map(\.actual), [1_500, 32])
        XCTAssertEqual(both.plan.sessions.count, 2)
        XCTAssertEqual(
            adherence.summary(of: entries),
            PlanAdherenceSummary(plannedTrainingDays: 2, trainedDays: 1, restDays: 1, restDaysKept: 1)
        )
    }

    func testAdherenceCountsADifferentSportOnAPlannedDay() {
        let plans = [ProgressV2Data.dayPlan(daysAgo: 2, [ProgressV2Data.daySession(.run, 45, minutes: 45)])]
        let workouts = [ProgressV2Data.workout(.bike, daysAgo: 2, minutes: 50, meters: 20_000)]

        let entries = adherence.entries(plans: plans, workouts: workouts, days: 7, now: TestFixtures.now)

        XCTAssertEqual(entries.map(\.outcome), [.followed])
        XCTAssertEqual(entries.first?.comparisons.map(\.sport), [SportID.run, SportID.bike])
    }

    func testAdherenceSummaryOfNothingIsZero() {
        XCTAssertEqual(
            adherence.summary(of: []),
            PlanAdherenceSummary(plannedTrainingDays: 0, trainedDays: 0, restDays: 0, restDaysKept: 0)
        )
    }

    // MARK: - Woche

    func testPlanAgainstActualRecognisesEverySport() throws {
        let plan = ProgressV2Data.week([
            ProgressV2Data.plannedDay("2026-09-28", [ProgressV2Data.session(.run, 40, minutes: 40)]),
            ProgressV2Data.plannedDay("2026-09-29", [ProgressV2Data.session(.bike, 60, minutes: 60), ProgressV2Data.session(.swim, 1_500, minutes: 30)]),
            ProgressV2Data.plannedDay("2026-09-30", [ProgressV2Data.session(.swim, 2_000, minutes: 40)]),
            ProgressV2Data.plannedDay("2026-10-01", []),
            ProgressV2Data.plannedDay("2026-10-02", [ProgressV2Data.session(.bike, 90, minutes: 90)]),
            // Keine Zeit: Was dort noch steht, zählt nicht.
            PlannedDay(
                date: "2026-10-03",
                content: PlannedDayContent(focus: "Laufen", sessions: [ProgressV2Data.session(.run, 30, minutes: 30)]),
                isUnavailable: true
            )
        ])
        let workouts = [
            ProgressV2Data.workout(.run, daysAgo: 2, minutes: 40, meters: 7_000, hour: 7),
            ProgressV2Data.workout(.bike, daysAgo: 1, minutes: 60, meters: 28_000, hour: 17),
            ProgressV2Data.workout(.swim, daysAgo: 0, minutes: 42, meters: 2_100, hour: 7),
            // Heute Abend, noch nicht geschehen.
            ProgressV2Data.workout(.bike, daysAgo: 0, minutes: 30, meters: 12_000, hour: 18)
        ]

        let result = statuses(plan, workouts)

        XCTAssertEqual(result.map(\.date), ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"])
        // Mo Laufen passt, Di nur Rad statt Rad und Schwimmen, Mi (heute) Schwimmen passt, Do und Fr kommen noch,
        // Sa keine Zeit, So ohne Plan.
        XCTAssertEqual(result.map(\.state), [.followed, .shorter, .followed, .upcoming, .upcoming, .skipped, .unplanned])
        let tuesday = try XCTUnwrap(result.first(where: { $0.date == "2026-09-29" }))
        XCTAssertEqual(tuesday.comparisons, [
            SportComparison(sport: .bike, unit: .minutes, planned: 60, actual: 60, plannedSessions: 1, workoutCount: 1, plannedMinutes: 60, actualMinutes: 60),
            SportComparison(sport: .swim, unit: .meters, planned: 1_500, actual: 0, plannedSessions: 1, workoutCount: 0, plannedMinutes: 30, actualMinutes: 0)
        ])
        XCTAssertEqual(tuesday.workoutCount, 1)
        XCTAssertEqual(tuesday.id, "2026-09-29")
        let today = try XCTUnwrap(result.first(where: { $0.date == "2026-09-30" }))
        XCTAssertEqual(today.comparisons.map(\.sport), [SportID.swim])
        XCTAssertEqual(today.comparisons.first?.actual, 2_100)
        let saturday = try XCTUnwrap(result.first(where: { $0.date == "2026-10-03" }))
        XCTAssertTrue(saturday.comparisons.isEmpty)
        XCTAssertEqual(saturday.day?.isUnavailable, true)

        let summary = weekProgress.summary(of: result)

        XCTAssertEqual(summary.plannedMinutes, 260)
        XCTAssertEqual(summary.actualMinutes, 142)
        XCTAssertEqual(summary.sessionsPlanned, 5)
        XCTAssertEqual(summary.sessionsDue, 4)
        XCTAssertEqual(summary.sessionsDone, 3)
        // Je Sportart in der Reihenfolge der Registry, nicht in der, in der sie vorkommen.
        XCTAssertEqual(summary.sports, [
            SportWeekTotal(sport: .swim, unit: .meters, planned: 3_500, actual: 2_100, plannedSessions: 2, workoutCount: 1),
            SportWeekTotal(sport: .bike, unit: .minutes, planned: 150, actual: 60, plannedSessions: 2, workoutCount: 1),
            SportWeekTotal(sport: .run, unit: .minutes, planned: 40, actual: 40, plannedSessions: 1, workoutCount: 1)
        ])
        XCTAssertEqual(summary.sports.map(\.id), [SportID.swim, SportID.bike, SportID.run])
    }

    func testWithoutAPlanEveryDayIsUnplannedButShowsWhatWasDone() throws {
        let workouts = [
            ProgressV2Data.workout(.bike, daysAgo: 2, minutes: 45, meters: 18_000, hour: 17),
            ProgressV2Data.workout(.swim, daysAgo: 2, minutes: 30, hour: 7)
        ]

        let result = statuses(nil, workouts)

        XCTAssertEqual(result.count, 7)
        XCTAssertTrue(result.allSatisfy { $0.state == .unplanned && $0.day == nil })
        let monday = try XCTUnwrap(result.first)
        XCTAssertEqual(monday.comparisons.map(\.sport), [SportID.swim, SportID.bike])
        XCTAssertEqual(monday.comparisons.map(\.unit), [PlanUnit.meters, PlanUnit.minutes])
        XCTAssertEqual(monday.workoutCount, 2)

        let summary = weekProgress.summary(of: result)

        XCTAssertEqual(summary.plannedMinutes, 0)
        XCTAssertEqual(summary.actualMinutes, 75, accuracy: 0.001)
        XCTAssertEqual(summary.sessionsDue, 0)
        XCTAssertEqual(summary.sessionsDone, 0)
        XCTAssertEqual(summary.sessionsPlanned, 0)
        XCTAssertEqual(summary.sports.map(\.sport), [SportID.swim, SportID.bike])
        XCTAssertEqual(summary.sports.map(\.plannedSessions), [0, 0])
        XCTAssertEqual(summary.sports.map(\.workoutCount), [1, 1])
    }

    func testPastDaysAreMissedOrRestAndTodayStaysOpen() {
        let plan = ProgressV2Data.week([
            ProgressV2Data.plannedDay("2026-09-28", [ProgressV2Data.session(.bike, 60, minutes: 60)]),
            ProgressV2Data.plannedDay("2026-09-29", []),
            ProgressV2Data.plannedDay("2026-09-30", [ProgressV2Data.session(.run, 40, minutes: 40)])
        ])

        // Nichts gemacht: Montag verpasst, Dienstag Ruhe gehalten, heute noch offen.
        XCTAssertEqual(statuses(plan).prefix(3).map(\.state), [.missed, .restKept, .today])

        // Dienstag doch gelaufen, heute erst 10 von 40 Minuten.
        let workouts = [
            ProgressV2Data.workout(.run, daysAgo: 1, minutes: 30),
            ProgressV2Data.workout(.run, daysAgo: 0, minutes: 10, hour: 7)
        ]
        XCTAssertEqual(statuses(plan, workouts).prefix(3).map(\.state), [.missed, .restBroken, .today])

        // Ein verpasster Tag zählt als fällig, aber nicht als erledigt; heute zählt noch nicht.
        let summary = weekProgress.summary(of: statuses(plan, workouts))
        XCTAssertEqual(summary.sessionsDue, 1)
        XCTAssertEqual(summary.sessionsDone, 0)
        XCTAssertEqual(summary.sessionsPlanned, 2)
        XCTAssertEqual(summary.plannedMinutes, 100)
        XCTAssertEqual(summary.actualMinutes, 40)
    }

    func testTodayAsRestDay() {
        let plan = ProgressV2Data.week([ProgressV2Data.plannedDay("2026-09-30", [])])

        XCTAssertEqual(state("2026-09-30", plan), .today)
        XCTAssertEqual(state("2026-09-30", plan, [ProgressV2Data.workout(.swim, daysAgo: 0, minutes: 20, meters: 800, hour: 7)]), .restBroken)
    }

    func testFutureDaysAreUpcomingAndFutureWorkoutsAreIgnored() {
        let plan = ProgressV2Data.week([
            ProgressV2Data.plannedDay("2026-09-30", [ProgressV2Data.session(.run, 40, minutes: 40)]),
            ProgressV2Data.plannedDay("2026-10-02", [ProgressV2Data.session(.bike, 60, minutes: 60)])
        ])

        XCTAssertEqual(state("2026-10-02", plan), .upcoming)
        // Um 20 Uhr ist noch nicht geschehen: heute bleibt offen.
        XCTAssertEqual(state("2026-09-30", plan, [ProgressV2Data.workout(.run, daysAgo: 0, minutes: 40, hour: 20)]), .today)
    }

    func testADayWithoutTimeIsSkippedEvenWithAWorkout() throws {
        let unavailable = PlannedDay(
            date: "2026-09-28",
            content: PlannedDayContent.rest(focus: "Keine Zeit"),
            isUnavailable: true,
            contentBeforeUnavailable: PlannedDayContent(focus: "Rad", sessions: [ProgressV2Data.session(.bike, 60, minutes: 60)])
        )
        let result = statuses(ProgressV2Data.week([unavailable]), [ProgressV2Data.workout(.run, daysAgo: 2, minutes: 30)])

        let monday = try XCTUnwrap(result.first)
        XCTAssertEqual(monday.state, .skipped)
        XCTAssertEqual(monday.comparisons.map(\.isPlanned), [false])
        XCTAssertEqual(monday.workoutCount, 1)
        let summary = weekProgress.summary(of: result)
        XCTAssertEqual(summary.sessionsDue, 0)
        XCTAssertEqual(summary.plannedMinutes, 0)
        XCTAssertEqual(summary.actualMinutes, 30)
    }

    func testAPlannedSportTheAppDoesNotKnowComesLastInTheWeekTotals() {
        let kayak = SportID(rawValue: "kayak")
        let kayakSession = WeekSession(
            sport: kayak, sessionType: .endurance, intensity: .easy, amount: 30, unit: .minutes,
            minutes: 30, distanceMeters: 6_000, focus: "Kajak"
        )
        let plan = ProgressV2Data.week([
            ProgressV2Data.plannedDay("2026-10-01", [kayakSession, ProgressV2Data.session(.run, 30, minutes: 30)])
        ])

        let summary = weekProgress.summary(of: statuses(plan))

        XCTAssertEqual(summary.sports.map(\.sport), [SportID.run, kayak])
        XCTAssertEqual(summary.sessionsPlanned, 2)
    }
}
