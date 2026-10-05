import XCTest
@testable import SwimInstructorCore

final class PerformanceEstimatorTests: XCTestCase {
    private let now = TestFixtures.now

    private func input(
        workouts: [Workout] = [], resting: [Double?] = [], observed: [Double] = [], age: Int? = nil
    ) -> PerformanceEstimationInput {
        // resting[0] ist heute, resting[1] gestern ...
        let vitals = resting.enumerated().map { day, value in
            DailyVitals(date: TestFixtures.date(daysAgo: day, hour: 0), restingHeartRate: value)
        }
        return PerformanceEstimationInput(now: now, workouts: workouts, vitals: vitals, dailyMaximumHeartRates: observed, age: age)
    }

    /// Lauf über 30 Minuten mit Puls 90 über einem Ruhepuls von 52.
    private func run(meters: Double, daysAgo: Int = 3, minutes: Double = 30, heartRate: Double? = 142) -> Workout {
        TestFixtures.workout(.run, daysAgo: daysAgo, minutes: minutes, meters: meters, heartRate: heartRate)
    }

    // MARK: - Werte für alle Sportarten

    func testMaximumHeartRateMeasuredAndByFormulaAndRestingHeartRateOfTheLastSevenMeasuredDays() {
        let estimates = PerformanceEstimator().athleteEstimates(input(
            resting: [50, 52, 54, nil, 56, 58, 60, 62, 64, 66], observed: [175, 193, 191.4], age: 40
        ))
        XCTAssertEqual(estimates, [
            PerformanceEstimate(metric: .maxHeartRate, value: 191, source: .estimated),
            // Tanaka: 208 − 0,7 × 40.
            PerformanceEstimate(metric: .maxHeartRate, value: 180, source: .formula),
            // Tage 0 bis 7 ohne den Tag ohne Messung: 50 bis 62 im Schnitt.
            PerformanceEstimate(metric: .restingHeartRate, value: 56, source: .estimated)
        ])
    }

    func testASingleSpikeOfTheSensorIsNoMaximumHeartRate() {
        // Ein Tag mit 230 (Ausreißer), sonst höchstens 186.
        let maxima: [Double] = [230, 186, 184, 150, 120]
        XCTAssertEqual(PerformanceEstimator.observedMaximumHeartRate(dailyMaxima: maxima, age: nil), 186, "zweithöchster Tag")
        XCTAssertNil(PerformanceEstimator.observedMaximumHeartRate(dailyMaxima: [230], age: nil), "ein Tag reicht nicht")
    }

    func testMeasuredMaximumHeartRateFarAboveTheFormulaIsDropped() {
        // 40 Jahre: Faustformel 180, gemessen zählt bis 200.
        let maxima: [Double] = [230, 228, 199, 196]
        XCTAssertEqual(PerformanceEstimator.observedMaximumHeartRate(dailyMaxima: maxima, age: 40), 196)
        let resolved = PerformanceEstimator().resolve(profile: .empty, input: input(observed: [230, 229, 225], age: 40))
        XCTAssertEqual(resolved.value(.maxHeartRate)?.value, 180)
        XCTAssertEqual(resolved.value(.maxHeartRate)?.source, .formula)
    }

    func testMeasuredMaximumHeartRateBelowTheFormulaKeepsTheFormula() {
        // Nie am Anschlag trainiert: 170 ist nur eine Untergrenze, die Faustformel (180) bleibt.
        XCTAssertNil(PerformanceEstimator.observedMaximumHeartRate(dailyMaxima: [172, 170], age: 40))
        let resolved = PerformanceEstimator().resolve(profile: .empty, input: input(observed: [172, 170], age: 40))
        XCTAssertEqual(resolved.value(.maxHeartRate)?.value, 180)
    }

    func testWithoutHealthDataThereIsNothingToEstimate() {
        XCTAssertTrue(PerformanceEstimator().athleteEstimates(input(age: 0)).isEmpty)
        let resolved = PerformanceEstimator().resolve(profile: .empty, input: input())
        XCTAssertTrue(resolved.values.isEmpty)
    }

    // MARK: - Je Sportart

    func testOnlyAgeGivesFormulaValuesForBikeAndRun() {
        let resolved = PerformanceEstimator().resolve(profile: .empty, input: input(age: 40))

        XCTAssertEqual(resolved.value(.maxHeartRate)?.value, 180)
        XCTAssertEqual(resolved.value(.thresholdHeartRate, sport: .bike)?.value, 153, "85 % von 180")
        XCTAssertEqual(resolved.value(.thresholdHeartRate, sport: .run)?.value, 158, "88 % von 180")
        XCTAssertEqual(resolved.value(.thresholdHeartRate, sport: .run)?.source, .formula)
        XCTAssertEqual(resolved.value(.thresholdHeartRate, sport: .run)?.measuredAt, now)
        XCTAssertNil(resolved.value(.criticalSwimPace, sport: .swim))
        XCTAssertNil(resolved.value(.thresholdPacePerKilometer, sport: .run), "ohne Ruhepuls kein Schwellentempo")
    }

    func testSwimCSSIsTheFastestSessionPaceFromFourHundredMeters() {
        let swims = [
            TestFixtures.workout(.swim, daysAgo: 1, minutes: 40, meters: 2000),
            TestFixtures.workout(.swim, daysAgo: 5, minutes: 18, meters: 1000),
            // Zu kurz, zählt nicht.
            TestFixtures.workout(.swim, daysAgo: 6, minutes: 4, meters: 300),
            TestFixtures.workout(.swim, daysAgo: 7, minutes: 30, meters: nil)
        ]
        let resolved = PerformanceEstimator().resolve(profile: .empty, input: input(workouts: swims))
        XCTAssertEqual(resolved.value(.criticalSwimPace, sport: .swim)?.value, 108)
        XCTAssertEqual(resolved.value(.criticalSwimPace, sport: .swim)?.source, .estimated)

        let tooShort = PerformanceEstimator().resolve(profile: .empty, input: input(workouts: [swims[2], swims[3]]))
        XCTAssertNil(tooShort.value(.criticalSwimPace, sport: .swim))
    }

    func testTestedCSSBeatsTheEstimate() {
        let profile = PerformanceProfile(values: [TestFixtures.performance(.criticalSwimPace, 105, .tested, sport: .swim, daysAgo: 10)])
        let resolved = PerformanceEstimator().resolve(
            profile: profile,
            input: input(workouts: [TestFixtures.workout(.swim, daysAgo: 1, minutes: 18, meters: 1000)])
        )
        XCTAssertEqual(resolved.value(.criticalSwimPace, sport: .swim)?.value, 105)
        XCTAssertEqual(resolved.value(.criticalSwimPace, sport: .swim)?.source, .tested)
    }

    func testRunThresholdPaceFromHeartRateAndSpeedOfRuns() {
        let resolved = PerformanceEstimator().resolve(
            profile: .empty,
            input: input(workouts: [run(meters: 4944), run(meters: 4944, daysAgo: 6)], resting: [52], observed: [188, 188])
        )
        XCTAssertEqual(resolved.value(.thresholdHeartRate, sport: .run)?.value, 165)
        // 4944 m in 30 min bei 90 über Ruhe; am Schwellenpuls 113 über Ruhe: 3,45 m/s, also 4:50 pro km.
        XCTAssertEqual(resolved.value(.thresholdPacePerKilometer, sport: .run)?.value, 290)
        XCTAssertEqual(resolved.value(.thresholdPacePerKilometer, sport: .run)?.source, .estimated)
    }

    func testRunThresholdPaceUsesAConfirmedThresholdHeartRate() {
        let profile = PerformanceProfile(values: [TestFixtures.performance(.thresholdHeartRate, 170, .tested, sport: .run, daysAgo: 20)])
        let resolved = PerformanceEstimator().resolve(
            profile: profile,
            input: input(workouts: [run(meters: 4944), run(meters: 4944, daysAgo: 6)], resting: [52], observed: [188, 188])
        )
        XCTAssertEqual(resolved.value(.thresholdHeartRate, sport: .run)?.value, 170)
        XCTAssertEqual(resolved.value(.thresholdPacePerKilometer, sport: .run)?.value, 278)
    }

    func testRunThresholdPaceUsesTheMedianOfQualifyingRuns() {
        let pace = { (runs: [Workout]) in RunModule.thresholdPace(runs, thresholdHeartRate: 165, restingHeartRate: 52) }

        XCTAssertEqual(pace([run(meters: 4500), run(meters: 4944), run(meters: 5400)]), 290, "ungerade: der mittlere")
        XCTAssertEqual(pace([run(meters: 4000), run(meters: 4500), run(meters: 4944), run(meters: 5400)]), 304, "gerade: Mittel der beiden mittleren")
        XCTAssertNil(pace([
            run(meters: 4944),
            run(meters: 1500, minutes: 10),
            run(meters: 4944, minutes: 14),
            run(meters: 4944, heartRate: nil),
            run(meters: 4944, heartRate: 70),
            run(meters: 1900)
        ]), "nur ein Lauf reicht nicht")
        XCTAssertNil(RunModule.thresholdPace([run(meters: 4944), run(meters: 4944)], thresholdHeartRate: 50, restingHeartRate: 52))
    }

    func testBikeWithoutMaximumHeartRateEstimatesNothing() {
        let context = PerformanceEstimationContext(
            sport: .bike, now: now, workouts: [], known: ResolvedPerformance(profile: .empty, estimates: [])
        )
        XCTAssertTrue(BikeModule().estimatePerformance(context).isEmpty)
        XCTAssertTrue(RunModule().estimatePerformance(context).isEmpty)
        XCTAssertNil(context.maximumHeartRate)
        XCTAssertNil(context.restingHeartRate)
        XCTAssertNil(context.value(.thresholdHeartRate))
    }

    func testEveryRegisteredSportGetsItsOwnEstimates() throws {
        let registry = try SportRegistry(modules: [SwimModule(), RowingTestModule()])
        let rowing = TestFixtures.workout("rowing", daysAgo: 2, minutes: 16, meters: 4000)
        let resolved = PerformanceEstimator(registry: registry).resolve(profile: .empty, input: input(workouts: [rowing]))
        XCTAssertEqual(resolved.value(RowingTestModule.twoKilometerTime, sport: "rowing")?.value, 480)
    }
}
