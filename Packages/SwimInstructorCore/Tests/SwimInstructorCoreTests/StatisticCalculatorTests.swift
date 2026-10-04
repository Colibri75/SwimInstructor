import XCTest
@testable import SwimInstructorCore

/// Feste Daten für die Rechentests der Statistik. "Heute" ist Mittwoch, der 30.09.2026, 12 Uhr (TestFixtures.now); die
/// 7 Tage reichen vom 24. bis 30.09., die Woche beginnt am Montag, dem 28.09.
enum StatisticData {
    static let registry = try! SportRegistry(modules: [SwimModule(), BikeModule(), RunModule(), RowingTestModule()])

    static func workout(
        _ sport: SportID, daysAgo: Int, minutes: Double, meters: Double? = nil, heartRate: Double? = nil,
        metrics: [WorkoutMetric: Double] = [:]
    ) -> Workout {
        let start = TestFixtures.date(daysAgo: daysAgo, hour: 8)
        return Workout(
            id: UUID(), sport: sport, startDate: start, endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60, distanceMeters: meters, averageHeartRate: heartRate, metrics: metrics
        )
    }

    /// In den 7 Tagen: je zwei Einheiten Schwimmen, Rad und Laufen, einmal Rudern. Davor: Schwimmen am Dienstag der
    /// Vorwoche und ein Lauf.
    static let workouts: [Workout] = [
        workout("swim", daysAgo: 1, minutes: 40, meters: 2000, heartRate: 140, metrics: [.strokes: 1600]),
        workout("swim", daysAgo: 4, minutes: 30, meters: 1500, heartRate: 130, metrics: [.strokes: 1350]),
        workout("bike", daysAgo: 2, minutes: 90, meters: 45000, heartRate: 135,
                metrics: [.averagePower: 200, .averageCadence: 85, .elevationGain: 450]),
        workout("bike", daysAgo: 5, minutes: 60, meters: 27000, metrics: [.averagePower: 180, .elevationGain: 150]),
        workout("run", daysAgo: 0, minutes: 50, meters: 10000, heartRate: 150, metrics: [.averagePower: 250, .elevationGain: 80]),
        workout("run", daysAgo: 3, minutes: 30, meters: 6000, heartRate: 145),
        workout("rowing", daysAgo: 1, minutes: 25, heartRate: 128, metrics: [.averagePower: 160]),
        workout("swim", daysAgo: 8, minutes: 25, meters: 1000),
        workout("run", daysAgo: 10, minutes: 60, meters: 11000, heartRate: 140)
    ]

    static let vitals: [DailyVitals] = [
        DailyVitals(date: TestFixtures.date(daysAgo: 0, hour: 0), restingHeartRate: 50, hrvSDNN: 60),
        DailyVitals(date: TestFixtures.date(daysAgo: 1, hour: 0), restingHeartRate: 52, sleepHours: 7),
        DailyVitals(date: TestFixtures.date(daysAgo: 2, hour: 0), restingHeartRate: 54, sleepHours: 8),
        DailyVitals(date: TestFixtures.date(daysAgo: 3, hour: 0), hrvSDNN: 70, sleepHours: 7.5),
        DailyVitals(date: TestFixtures.date(daysAgo: 8, hour: 0), restingHeartRate: 56)
    ]

    static func session(_ sport: SportID, _ amount: Double, unit: PlanUnit, minutes: Double) -> DaySession {
        DaySession(
            sport: sport, sessionType: .endurance, intensity: .easy, focus: "Grundlage", amount: amount, unit: unit,
            distanceMeters: unit == .meters ? amount : minutes * 60 * 3, durationMinutes: minutes, steps: []
        )
    }

    static func plan(daysAgo: Int, _ sessions: [DaySession]) -> DayPlanV2Response {
        DayPlanV2Response(
            source: .claude, date: PlanFormatting.isoDay(TestFixtures.date(daysAgo: daysAgo, hour: 12), calendar: TestFixtures.utc),
            generatedAt: TestFixtures.now, stale: false, plan: DayPlanV2(rationale: "Test", sessions: sessions)
        )
    }

    /// Trainiert am Dienstag (Schwimmen) und Montag (Rad), nichts am 24.09., Ruhetag am 26.09. trotzdem geschwommen.
    static let plans: [DayPlanV2Response] = [
        plan(daysAgo: 1, [session("swim", 2000, unit: .meters, minutes: 40)]),
        plan(daysAgo: 2, [session("bike", 90, unit: .minutes, minutes: 90)]),
        plan(daysAgo: 4, []),
        plan(daysAgo: 6, [session("swim", 1500, unit: .meters, minutes: 30)])
    ]

    static let input = StatisticInput(workouts: workouts, vitals: vitals, plans: plans, now: TestFixtures.now)

    static let calculator = StatisticCalculator(calendar: TestFixtures.utc, registry: registry)

    static func result(_ sport: SportID?, _ metric: StatisticMetric, _ period: StatisticPeriod = .sevenDays,
                       input: StatisticInput = StatisticData.input) -> StatisticResult {
        calculator.result(for: StatisticTile(sport: sport, metric: metric, period: period), input: input)
    }
}

/// Jede Kennzahl mit festen Daten nachgerechnet.
final class StatisticCalculatorTests: XCTestCase {
    /// Erwartete Werte der 7 Tage für jede Kennzahl jedes Katalogs, auch der Test-Sportart Rudern.
    private static let expected: [String: Double] = [
        // Schwimmen: 3500 m in 70 min, Züge 2950.
        "swim/distance": 3500,
        "swim/pace_per_100m": 120,
        "swim/duration": 4200,
        "swim/sessions": 2,
        "swim/average_heart_rate": (140 * 2400 + 130 * 1800) / 4200.0,
        "swim/strokes_per_100m": 2950 / 3500.0 * 100,
        "swim/longest_distance": 2000,
        "swim/training_load": 70,
        // Rad: 72 km in 150 min, Puls und Trittfrequenz nur bei einer Fahrt.
        "bike/distance": 72000,
        "bike/speed": 8,
        "bike/duration": 9000,
        "bike/sessions": 2,
        "bike/average_heart_rate": 135,
        "bike/average_power": 192,
        "bike/average_cadence": 85,
        "bike/elevation_gain": 600,
        "bike/longest_distance": 45000,
        "bike/training_load": 120,
        // Laufen: 16 km in 80 min, Watt und Höhenmeter nur beim ersten Lauf.
        "run/distance": 16000,
        "run/pace_per_km": 300,
        "run/duration": 4800,
        "run/sessions": 2,
        "run/average_heart_rate": (150 * 3000 + 145 * 1800) / 4800.0,
        "run/average_power": 250,
        "run/elevation_gain": 80,
        "run/longest_distance": 10000,
        "run/training_load": 80,
        // Rudern ohne eigene Liste: Kennzahlen aus den Health-Angaben.
        "rowing/duration": 1500,
        "rowing/sessions": 1,
        "rowing/average_heart_rate": 128,
        "rowing/average_power": 160,
        "rowing/longest_duration": 1500,
        "rowing/training_load": 22.5,
        // Über alle Sportarten.
        "all/duration": 19500,
        "all/training_load": 292.5,
        "all/sessions": 7,
        "all/plan_adherence": 2 / 3.0,
        "all/resting_heart_rate": 52,
        "all/heart_rate_variability": 65,
        "all/sleep": 7.5 * 3600
    ]

    func testEveryMetricOfEveryCatalogMatchesTheFixedData() throws {
        var checked = Set<String>()
        let sports: [SportID?] = [nil] + StatisticData.registry.ids.map { Optional($0) }
        for sport in sports {
            for definition in StatisticData.registry.statistics(for: sport) {
                let key = "\(sport?.rawValue ?? "all")/\(definition.metric.rawValue)"
                checked.insert(key)
                let expected = try XCTUnwrap(Self.expected[key], "Kein Rechentest für \(key)")
                let result = StatisticData.result(sport, definition.metric)

                XCTAssertEqual(result.definition, definition, key)
                XCTAssertEqual(try XCTUnwrap(result.value, key), expected, accuracy: 0.0001, key)
            }
        }
        XCTAssertEqual(checked, Set(Self.expected.keys), "Erwartete Werte für Kennzahlen, die es nicht mehr gibt")
    }

    // MARK: - Einheiten

    func testPaceIsTotalTimeOverTotalDistanceLikeTheFitnessApp() {
        let result = StatisticData.result("run", .pacePerKilometer)

        XCTAssertEqual(result.value, 300)
        XCTAssertEqual(result.basis, .workouts(2))
        // 7 Tage davor: 60 min auf 11 km.
        XCTAssertEqual(try XCTUnwrap(result.previous), 3600 / 11.0, accuracy: 0.0001)
        XCTAssertEqual(StatisticFormatting.text(result.value, definition: result.definition), "5:00 /km")
    }

    func testOneRunGivesExactlyItsOwnPace() {
        let run = StatisticData.workout("run", daysAgo: 0, minutes: 52.5, meters: 10000)
        let input = StatisticInput(workouts: [run], now: TestFixtures.now)

        let result = StatisticData.result("run", .pacePerKilometer, .currentWeek, input: input)

        XCTAssertEqual(StatisticFormatting.text(result.value, definition: result.definition), "5:15 /km")
        XCTAssertEqual(StatisticFormatting.detail(result), "aus 1 Einheit")
    }

    func testAveragesWithoutDataHaveNoValueButTotalsAreZero() {
        let empty = StatisticInput(workouts: [], now: TestFixtures.now)

        for metric in [StatisticMetric.pacePerKilometer, .averageHeartRate, .averagePower, .longestDistance] {
            XCTAssertNil(StatisticData.result("run", metric, input: empty).value, metric.rawValue)
        }
        XCTAssertNil(StatisticData.result("rowing", .longestDuration, input: empty).value)
        XCTAssertNil(StatisticData.result("swim", .strokesPerHundredMeters, input: empty).value)
        for metric in [StatisticMetric.distance, .duration, .sessions, .elevationGain, .trainingLoad] {
            XCTAssertEqual(StatisticData.result("run", metric, input: empty).value, 0, metric.rawValue)
        }
    }

    func testATotalWithoutAnyMeasurementIsUnknownRatherThanZero() {
        let ride = StatisticData.workout("bike", daysAgo: 0, minutes: 60, meters: 30000)
        let input = StatisticInput(workouts: [ride], now: TestFixtures.now)

        XCTAssertNil(StatisticData.result("bike", .elevationGain, input: input).value)
    }

    func testUnitsWithoutDistanceOrDurationDoNotDistortPaceAndAverages() {
        let input = StatisticInput(workouts: [
            StatisticData.workout("run", daysAgo: 0, minutes: 30, meters: 6000, heartRate: 150),
            // Ohne Strecke (Laufband ohne Kalibrierung) und ohne Dauer (kaputter Eintrag).
            StatisticData.workout("run", daysAgo: 1, minutes: 20, heartRate: 160),
            StatisticData.workout("run", daysAgo: 2, minutes: 0, meters: 3000, heartRate: 170)
        ], now: TestFixtures.now)

        XCTAssertEqual(StatisticData.result("run", .pacePerKilometer, input: input).value, 300)
        XCTAssertEqual(StatisticData.result("run", .averageHeartRate, input: input).value, (150 * 1800 + 160 * 1200) / 3000.0)
        XCTAssertEqual(StatisticData.result("run", .longestDistance, input: input).value, 6000)
    }

    func testAveragesWithoutDurationCountEveryUnitAlike() {
        let input = StatisticInput(workouts: [
            StatisticData.workout("bike", daysAgo: 0, minutes: 0, metrics: [.averagePower: 200]),
            StatisticData.workout("bike", daysAgo: 1, minutes: 0, metrics: [.averagePower: 100, .averageCadence: .nan])
        ], now: TestFixtures.now)

        XCTAssertEqual(StatisticData.result("bike", .averagePower, input: input).value, 150)
        XCTAssertNil(StatisticData.result("bike", .averageCadence, input: input).value)
    }

    func testTrainingLoadUsesHeartRateWhenRestingAndMaximumAreKnown() throws {
        let input = StatisticInput(
            workouts: [StatisticData.workout("run", daysAgo: 0, minutes: 50, heartRate: 150), StatisticData.workout("run", daysAgo: 1, minutes: 30)],
            restingHeartRate: 50, maximumHeartRate: 190, now: TestFixtures.now
        )

        // Banister: 50 min × (100/140) × 0,64 × e^(1,92 × 100/140) ≈ 90,08; ohne Puls 30 min × 1,0.
        XCTAssertEqual(try XCTUnwrap(StatisticData.result("run", .trainingLoad, input: input).value), 90.0795 + 30, accuracy: 0.001)
    }

    // MARK: - Über alle Sportarten

    func testHoursBySportShowTheShareOfEverySport() {
        let result = StatisticData.result(nil, .duration)

        XCTAssertEqual(result.definition.displayName, "Stunden je Sportart")
        XCTAssertEqual(result.shares, [
            StatisticShare(sport: "swim", value: 4200), StatisticShare(sport: "bike", value: 9000),
            StatisticShare(sport: "run", value: 4800), StatisticShare(sport: "rowing", value: 1500)
        ])
        XCTAssertEqual(StatisticFormatting.detail(result, registry: StatisticData.registry), "Schwimmen 1:10 · Radfahren 2:30 · Laufen 1:20 · Rudern 0:25")
    }

    func testSharesKeepSportsThisVersionDoesNotKnowAtTheEnd() {
        let input = StatisticInput(workouts: [
            StatisticData.workout("yoga", daysAgo: 0, minutes: 60),
            StatisticData.workout("climbing", daysAgo: 1, minutes: 30),
            StatisticData.workout("run", daysAgo: 1, minutes: 45)
        ], now: TestFixtures.now)

        let result = StatisticData.result(nil, .sessions, input: input)

        XCTAssertEqual(result.value, 3)
        XCTAssertEqual(result.shares.map(\.sport), ["run", "climbing", "yoga"])
        XCTAssertTrue(StatisticData.result(nil, .restingHeartRate).shares.isEmpty, "Nur für Summen aus Einheiten")
        XCTAssertTrue(StatisticData.result("run", .duration).shares.isEmpty, "Nur über alle Sportarten")
    }

    func testVitalsAreTheMeanOfTheDaysWithAMeasurement() {
        let resting = StatisticData.result(nil, .restingHeartRate)

        XCTAssertEqual(resting.value, 52)
        XCTAssertEqual(resting.basis, .days(3))
        XCTAssertEqual(resting.previous, 56)
        XCTAssertEqual(StatisticFormatting.detail(resting), "an 3 Tagen gemessen")
        XCTAssertEqual(StatisticFormatting.text(StatisticData.result(nil, .sleep).value, definition: .sleep), "7:30 h")

        let none = StatisticData.result(nil, .heartRateVariability, input: StatisticInput(workouts: [], now: TestFixtures.now))
        XCTAssertNil(none.value)
        XCTAssertEqual(StatisticFormatting.detail(none), "keine Messung im Zeitraum")
    }

    func testPlanAdherenceCountsPastTrainingDaysLikeTheHistory() {
        let result = StatisticData.result(nil, .planAdherence)

        XCTAssertEqual(result.basis, .planDays(trained: 2, planned: 3))
        XCTAssertEqual(StatisticFormatting.text(result.value, definition: result.definition), "67 %")
        XCTAssertEqual(StatisticFormatting.detail(result), "2 von 3 Trainingstagen")
        // Diese Woche: Montag und Dienstag trainiert, wie geplant.
        XCTAssertEqual(StatisticData.result(nil, .planAdherence, .currentWeek).value, 1)

        let withoutPlan = StatisticData.result(nil, .planAdherence, input: StatisticInput(workouts: StatisticData.workouts, now: TestFixtures.now))
        XCTAssertNil(withoutPlan.value)
        XCTAssertEqual(StatisticFormatting.detail(withoutPlan), "kein Plan im Zeitraum")
    }

    // MARK: - Zeitraum, Vergleich, Verlauf

    func testTheWeekComparesWithTheSameDaysOfThePreviousWeek() {
        let result = StatisticData.result(nil, .duration, .currentWeek)

        // Montag bis heute: Rad 90, Schwimmen 40, Rudern 25, Laufen 50 Minuten.
        XCTAssertEqual(result.value, 12300)
        // Montag bis Mittwoch der Vorwoche: nur das Schwimmen am Dienstag.
        XCTAssertEqual(result.previous, 1500)
        XCTAssertEqual(result.series.map(\.value), [5400, 3900, 3000, nil, nil, nil, nil])
        XCTAssertEqual(result.series.first?.start, TestFixtures.date(daysAgo: 2, hour: 0))
    }

    func testSevenDaysHaveOnePointPerDay() {
        let result = StatisticData.result("run", .pacePerKilometer)

        XCTAssertEqual(result.series.map(\.value), [nil, nil, nil, 300, nil, nil, 300])
        XCTAssertEqual(result.series.map(\.start), (0..<7).map { TestFixtures.date(daysAgo: 6 - $0, hour: 0) })
    }

    func testWeeksHaveOnePointPerWeekAndEightWeeksNoComparison() {
        let fourWeeks = StatisticData.result("swim", .distance, .fourWeeks)
        let eightWeeks = StatisticData.result("swim", .distance, .eightWeeks)

        XCTAssertEqual(fourWeeks.series.map(\.value), [0, 0, 1000, 3500])
        XCTAssertEqual(fourWeeks.value, 4500)
        XCTAssertEqual(fourWeeks.previous, 0)
        XCTAssertEqual(eightWeeks.series.count, 8)
        XCTAssertEqual(eightWeeks.value, 4500)
        XCTAssertNil(eightWeeks.previous)
    }

    // MARK: - Auflösen

    func testTheResultShowsTheTileAsThisVersionCanShowIt() {
        let result = StatisticData.result("bike", .pacePerKilometer)

        XCTAssertEqual(result.tile.metric, .distance, "Rad hat keine Pace: die erste Kennzahl")
        XCTAssertEqual(result.value, 72000)
    }

    func testResultsKeepTheOrderOfTheTiles() {
        let tiles = [
            StatisticTile(sport: nil, metric: .planAdherence, period: .sevenDays),
            StatisticTile(sport: "run", metric: .distance, period: .sevenDays)
        ]

        let results = StatisticData.calculator.results(for: tiles, input: StatisticData.input)

        XCTAssertEqual(results.map(\.id), tiles.map(\.id))
        XCTAssertEqual(results.map(\.value), [2 / 3.0, 16000])
    }

    func testInputFromTheReadingTakesHeartRatesOfTheSnapshot() {
        let performance = AthleteStateSnapshot.PerformanceSummary(
            athlete: [
                .init(metric: .maxHeartRate, value: 190, source: .tested, measuredAt: TestFixtures.now),
                .init(metric: .restingHeartRate, value: 50, source: .estimated, measuredAt: TestFixtures.now)
            ],
            sports: []
        )
        let reading = AthleteStateReading(
            snapshot: TestFixtures.snapshot.withPerformance(performance), workouts: [], allWorkouts: StatisticData.workouts,
            vitals: StatisticData.vitals, vitalsAvailable: true
        )

        let input = StatisticInput(reading: reading, plans: StatisticData.plans, now: TestFixtures.now)

        XCTAssertEqual(input.restingHeartRate, 50)
        XCTAssertEqual(input.maximumHeartRate, 190)
        XCTAssertEqual(input.workouts, StatisticData.workouts)
        XCTAssertEqual(input.vitals, StatisticData.vitals)
        XCTAssertEqual(input.plans, StatisticData.plans)

        let withoutPerformance = StatisticInput(
            reading: AthleteStateReading(snapshot: TestFixtures.snapshot, workouts: [], vitalsAvailable: false), plans: [], now: TestFixtures.now
        )
        XCTAssertNil(withoutPerformance.restingHeartRate)
        XCTAssertNil(withoutPerformance.maximumHeartRate)
    }
}
