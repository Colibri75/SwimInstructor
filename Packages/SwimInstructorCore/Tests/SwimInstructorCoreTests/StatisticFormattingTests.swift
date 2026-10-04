import XCTest
@testable import SwimInstructorCore

/// Zeiträume der Kacheln und ihre Texte.
final class StatisticFormattingTests: XCTestCase {
    private func day(_ daysAgo: Int) -> Date {
        TestFixtures.date(daysAgo: daysAgo, hour: 0)
    }

    private func result(
        _ definition: StatisticDefinition, value: Double?, previous: Double? = nil, period: StatisticPeriod = .currentWeek,
        sport: SportID? = "run", shares: [StatisticShare] = [], basis: StatisticBasis? = nil
    ) -> StatisticResult {
        StatisticResult(
            tile: StatisticTile(sport: sport, metric: definition.metric, period: period), definition: definition,
            value: value, previous: previous, series: [], shares: shares, basis: basis
        )
    }

    // MARK: - Zeiträume

    func testIntervalsEndTonightAndCompareWithTheSameDaysBefore() {
        // Mittwoch, 30.09.2026.
        let now = TestFixtures.now
        let calendar = TestFixtures.utc

        XCTAssertEqual(StatisticPeriod.currentWeek.interval(now: now, calendar: calendar), StatisticInterval(start: day(2), end: day(-1)))
        XCTAssertEqual(StatisticPeriod.currentWeek.previousInterval(now: now, calendar: calendar), StatisticInterval(start: day(9), end: day(6)))
        XCTAssertEqual(StatisticPeriod.sevenDays.interval(now: now, calendar: calendar), StatisticInterval(start: day(6), end: day(-1)))
        XCTAssertEqual(StatisticPeriod.sevenDays.previousInterval(now: now, calendar: calendar), StatisticInterval(start: day(13), end: day(6)))
        XCTAssertEqual(StatisticPeriod.fourWeeks.interval(now: now, calendar: calendar), StatisticInterval(start: day(27), end: day(-1)))
        XCTAssertEqual(StatisticPeriod.fourWeeks.previousInterval(now: now, calendar: calendar), StatisticInterval(start: day(55), end: day(27)))
        XCTAssertEqual(StatisticPeriod.eightWeeks.interval(now: now, calendar: calendar), StatisticInterval(start: day(55), end: day(-1)))
        XCTAssertNil(StatisticPeriod.eightWeeks.previousInterval(now: now, calendar: calendar))
    }

    func testEveryPeriodFitsTheDaysTheAppReads() {
        for period in StatisticPeriod.allCases {
            let earliest = period.previousInterval(now: TestFixtures.now, calendar: TestFixtures.utc)?.start
                ?? period.interval(now: TestFixtures.now, calendar: TestFixtures.utc).start
            XCTAssertGreaterThanOrEqual(earliest, day(SnapshotBuilder.workoutWindowDays - 1), period.rawValue)
            XCTAssertGreaterThanOrEqual(earliest, day(SnapshotBuilder.vitalsWindowDays - 1), period.rawValue)
        }
    }

    func testTheWeekStartsOnMonday() {
        let monday = TestFixtures.date(daysAgo: 2, hour: 7)
        let sunday = TestFixtures.date(daysAgo: -4, hour: 22)

        XCTAssertEqual(StatisticPeriod.currentWeek.interval(now: monday, calendar: TestFixtures.utc).start, day(2))
        XCTAssertEqual(StatisticPeriod.currentWeek.interval(now: sunday, calendar: TestFixtures.utc), StatisticInterval(start: day(2), end: day(-5)))
    }

    func testBucketsAreDaysOrWeeks() {
        let calendar = TestFixtures.utc

        XCTAssertEqual(StatisticPeriod.currentWeek.buckets(now: TestFixtures.now, calendar: calendar).map(\.start), (0..<7).map { day(2 - $0) })
        XCTAssertEqual(StatisticPeriod.sevenDays.buckets(now: TestFixtures.now, calendar: calendar).map(\.start), (0..<7).map { day(6 - $0) })
        XCTAssertEqual(
            StatisticPeriod.fourWeeks.buckets(now: TestFixtures.now, calendar: calendar),
            (0..<4).map { StatisticInterval(start: day(27 - $0 * 7), end: day(20 - $0 * 7)) }
        )
        XCTAssertEqual(StatisticPeriod.eightWeeks.buckets(now: TestFixtures.now, calendar: calendar).count, 8)
    }

    func testDaysStayDaysAcrossTheChangeToWinterTime() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        // Dienstag, 27.10.2026; am Sonntag davor endete die Sommerzeit.
        let now = try XCTUnwrap(berlin.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12)))

        let buckets = StatisticPeriod.sevenDays.buckets(now: now, calendar: berlin)

        XCTAssertEqual(buckets.map { berlin.component(.day, from: $0.start) }, [21, 22, 23, 24, 25, 26, 27])
        XCTAssertTrue(buckets.allSatisfy { berlin.component(.hour, from: $0.start) == 0 && $0.end == berlin.date(byAdding: .day, value: 1, to: $0.start) })
        XCTAssertEqual(buckets[4].end.timeIntervalSince(buckets[4].start), 25 * 3600, "Der Sonntag hat 25 Stunden")
    }

    func testIntervalIncludesItsStartButNotItsEnd() {
        let interval = StatisticInterval(start: day(1), end: day(0))

        XCTAssertTrue(interval.contains(day(1)))
        XCTAssertTrue(interval.contains(day(0).addingTimeInterval(-1)))
        XCTAssertFalse(interval.contains(day(0)))
    }

    func testPeriodNames() {
        XCTAssertEqual(StatisticPeriod.allCases.map(\.displayName), ["Diese Woche", "7 Tage", "4 Wochen", "8 Wochen"])
        XCTAssertEqual(StatisticPeriod.allCases.map(\.comparisonName), ["Vorwoche", "7 Tage davor", "4 Wochen davor", nil])
        XCTAssertEqual(StatisticPeriod.standard, .fourWeeks)
    }

    // MARK: - Werte

    func testValueInEveryFormat() {
        XCTAssertEqual(StatisticFormatting.value(12400, format: .meters), "12.400")
        XCTAssertEqual(StatisticFormatting.value(123_456, format: .kilometers), "123,5")
        XCTAssertEqual(StatisticFormatting.value(1_234_500, format: .kilometers), "1.234,5")
        XCTAssertEqual(StatisticFormatting.value(19800, format: .hours), "5:30")
        XCTAssertEqual(StatisticFormatting.value(59, format: .hours), "0:01")
        XCTAssertEqual(StatisticFormatting.value(312, format: .pace), "5:12")
        XCTAssertEqual(StatisticFormatting.value(359.6, format: .pace), "6:00")
        XCTAssertEqual(StatisticFormatting.value(7.9, format: .kilometersPerHour), "28,4")
        XCTAssertEqual(StatisticFormatting.value(1240.4, format: .integer), "1.240")
        XCTAssertEqual(StatisticFormatting.value(-0.2, format: .integer), "0")
        XCTAssertEqual(StatisticFormatting.value(0.854, format: .percent), "85")
    }

    func testNoValueIsADash() {
        XCTAssertEqual(StatisticFormatting.value(nil, format: .pace), "–")
        XCTAssertEqual(StatisticFormatting.value(.infinity, format: .integer), "–")
        XCTAssertEqual(StatisticFormatting.text(nil, definition: .pacePerKilometer), "–")
        XCTAssertEqual(StatisticFormatting.text(.nan, definition: .pacePerKilometer), "–")
    }

    func testTextAddsTheUnit() {
        XCTAssertEqual(StatisticFormatting.text(312, definition: .pacePerKilometer), "5:12 /km")
        XCTAssertEqual(StatisticFormatting.text(108, definition: .pacePerHundredMeters), "1:48 /100 m")
        XCTAssertEqual(StatisticFormatting.text(0.75, definition: .planAdherence), "75 %")
        XCTAssertEqual(StatisticFormatting.text(4, definition: .sessions), "4", "Anzahl ohne Einheit")
    }

    func testSportNameAndSymbol() {
        XCTAssertEqual(StatisticFormatting.sportName(nil), "Alle Sportarten")
        XCTAssertEqual(StatisticFormatting.sportName("run"), "Laufen")
        XCTAssertEqual(StatisticFormatting.sportName("kayak"), "kayak")
        XCTAssertEqual(StatisticFormatting.symbolName(nil), "square.grid.2x2")
        XCTAssertEqual(StatisticFormatting.symbolName("run"), "figure.run")
    }

    // MARK: - Vergleich

    func testTrendAndWhetherItIsGood() {
        let faster = result(.pacePerKilometer, value: 300, previous: 320)
        let slower = result(.pacePerKilometer, value: 320, previous: 300)
        let more = result(.distanceKilometers, value: 30000, previous: 20000)
        let better = result(.heartRateVariability, value: 70, previous: 60)

        XCTAssertEqual(StatisticFormatting.trend(faster), .down)
        XCTAssertEqual(StatisticFormatting.assessment(faster), .better)
        XCTAssertEqual(StatisticFormatting.assessment(slower), .worse)
        XCTAssertEqual(StatisticFormatting.trend(more), .up)
        XCTAssertEqual(StatisticFormatting.assessment(more), .neutral, "Mehr Umfang ist nicht automatisch besser")
        XCTAssertEqual(StatisticFormatting.assessment(better), .better)
    }

    func testSmallOrMissingChanges() {
        XCTAssertEqual(StatisticFormatting.trend(result(.pacePerKilometer, value: 300, previous: 301)), .flat)
        XCTAssertEqual(StatisticFormatting.assessment(result(.pacePerKilometer, value: 300, previous: 301)), .neutral)
        XCTAssertEqual(StatisticFormatting.trend(result(.sessions, value: 0, previous: 0)), .flat)
        XCTAssertEqual(StatisticFormatting.trend(result(.sessions, value: 2, previous: 0)), .up)
        XCTAssertNil(StatisticFormatting.trend(result(.sessions, value: 2, previous: nil)))
        XCTAssertNil(StatisticFormatting.trend(result(.sessions, value: nil, previous: 2)))
        XCTAssertEqual(StatisticFormatting.assessment(result(.sessions, value: nil, previous: 2)), .neutral)
    }

    func testComparisonNamesThePeriodBefore() {
        XCTAssertEqual(StatisticFormatting.comparison(result(.pacePerKilometer, value: 300, previous: 320)), "Vorwoche: 5:20 /km")
        XCTAssertEqual(StatisticFormatting.comparison(result(.pacePerKilometer, value: 300, period: .sevenDays)), "7 Tage davor: –")
        XCTAssertNil(StatisticFormatting.comparison(result(.pacePerKilometer, value: 300, period: .eightWeeks)))
    }

    // MARK: - Zeile unter dem Wert

    func testDetailSaysWhatTheValueIsBasedOn() {
        XCTAssertEqual(StatisticFormatting.detail(result(.pacePerKilometer, value: 300, basis: .workouts(1))), "aus 1 Einheit")
        XCTAssertEqual(StatisticFormatting.detail(result(.pacePerKilometer, value: 300, basis: .workouts(3))), "aus 3 Einheiten")
        XCTAssertEqual(StatisticFormatting.detail(result(.restingHeartRate, value: 50, sport: nil, basis: .days(1))), "an 1 Tag gemessen")
        XCTAssertEqual(StatisticFormatting.detail(result(.planAdherence, value: 0.5, sport: nil, basis: .planDays(trained: 2, planned: 4))), "2 von 4 Trainingstagen")
        XCTAssertNil(StatisticFormatting.detail(result(.distanceKilometers, value: 0)))
        XCTAssertEqual(StatisticFormatting.detail(result(.pacePerKilometer, value: nil)), "keine passende Einheit im Zeitraum")
    }

    func testAccessibilityLabelReadsEverything() {
        let label = StatisticFormatting.accessibilityLabel(result(.pacePerKilometer, value: 300, previous: 320, basis: .workouts(2)))

        XCTAssertEqual(label, "Laufen, Pace pro km, Diese Woche: 5:00 /km. Vorwoche: 5:20 /km. aus 2 Einheiten")
        XCTAssertEqual(
            StatisticFormatting.accessibilityLabel(result(.sessions, value: 3, period: .eightWeeks, sport: nil)),
            "Alle Sportarten, Einheiten, 8 Wochen: 3"
        )
    }
}
