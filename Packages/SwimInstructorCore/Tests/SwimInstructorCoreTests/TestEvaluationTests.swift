import XCTest
@testable import SwimInstructorCore

final class TestEvaluationTests: XCTestCase {
    // MARK: - Helfer

    private func module(_ sport: SportID) throws -> any SportModule {
        try XCTUnwrap(SportRegistry.standard.module(for: sport), "\(sport)")
    }

    /// Ein Test eines echten Moduls.
    private func realTest(_ sport: SportID, _ id: String) throws -> PerformanceTest {
        let tests: [PerformanceTest] = try module(sport).performanceTests
        let found: PerformanceTest? = tests.first(where: { (test: PerformanceTest) -> Bool in test.id == id })
        return try XCTUnwrap(found, "\(sport) \(id)")
    }

    private func definitions(_ sport: SportID) throws -> [PerformanceMetricDefinition] {
        try module(sport).performanceMetrics
    }

    /// Ein frei gebauter Test für die Grenzfälle der Auswertung.
    private func customTest(
        produces: [PerformanceMetric],
        inputs: [TestInput],
        evaluation: TestEvaluation
    ) -> PerformanceTest {
        PerformanceTest(
            id: "custom_test", displayName: "Eigener Test", produces: produces, maximalEffort: true, durationMinutes: 10,
            inputs: inputs, evaluation: evaluation
        )
    }

    private let timeA = TestInput(id: "time_a", label: "Zeit A", unit: "s", range: 60...1000)
    private let timeB = TestInput(id: "time_b", label: "Zeit B", unit: "s", range: 30...500)

    // MARK: - Neue Felder des Leistungstests

    func testPerformanceTestDefaultsToDirectEvaluationWithoutOwnInputs() {
        let test = PerformanceTest(id: "ramp", displayName: "Rampe", produces: [.thresholdPower], maximalEffort: true, durationMinutes: 20)

        XCTAssertTrue(test.inputs.isEmpty)
        XCTAssertEqual(test.evaluation, .direct)
        XCTAssertEqual(test.resultHint, "")
    }

    func testTestInputIsRequiredByDefault() {
        let input = TestInput(id: "time_400m", label: "Zeit 400 m", unit: "s", range: 180...1500)

        XCTAssertFalse(input.isOptional)
        XCTAssertEqual(input.id, "time_400m")
        XCTAssertEqual(input.label, "Zeit 400 m")
        XCTAssertEqual(input.unit, "s")
        XCTAssertEqual(input.range.lowerBound, 180)
        XCTAssertEqual(input.range.upperBound, 1500)
        XCTAssertTrue(TestInput(id: "power", label: "Leistung", unit: "W", range: 50...600, isOptional: true).isOptional)
    }

    func testRealTestsDescribeHowTheyAreEvaluated() throws {
        let css = try realTest(.swim, "css_400_200")
        XCTAssertEqual(css.evaluation, .criticalSwimPace(longInput: "time_400m", longMeters: 400, shortInput: "time_200m", shortMeters: 200))
        XCTAssertEqual(css.inputs.map(\.id), ["time_400m", "time_200m"])

        let timeTrial = try realTest(.swim, "time_trial_1000m")
        XCTAssertEqual(timeTrial.evaluation, .pacePerHundredMeters(input: "time_1000m", meters: 1000))
        XCTAssertEqual(timeTrial.inputs.map(\.id), ["time_1000m"])

        XCTAssertEqual(try realTest(.bike, "threshold_30min").evaluation, .direct)
        XCTAssertEqual(try realTest(.run, "threshold_30min").evaluation, .direct)
        XCTAssertEqual(try realTest(.run, "entry_easy_25min").evaluation, .direct)
    }

    func testEveryRealTestHasAResultHint() throws {
        for module in SportRegistry.standard.modules {
            for test in module.performanceTests {
                XCTAssertFalse(test.resultHint.isEmpty, "\(module.id) \(test.id)")
            }
        }
    }

    // MARK: - Eingaben

    func testExplicitInputsAreUsedAsTheyAre() throws {
        let css = try realTest(.swim, "css_400_200")

        let inputs = css.resultInputs(definitions: try definitions(.swim))

        XCTAssertEqual(inputs, css.inputs)
        XCTAssertEqual(inputs.map(\.unit), ["s", "s"])
        XCTAssertEqual(inputs.map(\.isOptional), [false, false])
        // Eigene Eingaben gelten auch ohne Definitionen.
        XCTAssertEqual(css.resultInputs(definitions: []), css.inputs)
    }

    func testWithoutOwnInputsEachProducedMetricGetsAnOptionalField() throws {
        let bike = try realTest(.bike, "threshold_30min")
        XCTAssertTrue(bike.inputs.isEmpty)

        let inputs = bike.resultInputs(definitions: try definitions(.bike))

        let expected: [TestInput] = [
            TestInput(id: "threshold_heart_rate", label: "Schwellenpuls", unit: "bpm", range: 100...215, isOptional: true),
            TestInput(id: "threshold_power", label: "Schwellenleistung (FTP)", unit: "W", range: 50...600, isOptional: true)
        ]
        XCTAssertEqual(inputs, expected)
    }

    func testRunThresholdTestAsksForHeartRateAndPaceBothOptional() throws {
        let threshold = try realTest(.run, "threshold_30min")

        let inputs = threshold.resultInputs(definitions: try definitions(.run))

        XCTAssertEqual(inputs.map(\.id), ["threshold_heart_rate", "threshold_pace_per_km"])
        XCTAssertEqual(inputs.map(\.unit), ["bpm", "s/km"])
        XCTAssertEqual(inputs.map(\.isOptional), [true, true])
    }

    func testASingleProducedMetricIsNotOptional() throws {
        let entry = try realTest(.run, "entry_easy_25min")

        let inputs = entry.resultInputs(definitions: try definitions(.run))

        let expected: [TestInput] = [
            TestInput(id: "threshold_pace_per_km", label: "Schwellentempo", unit: "s/km", range: 150...900)
        ]
        XCTAssertEqual(inputs, expected)
        XCTAssertEqual(inputs.first?.isOptional, false)
    }

    func testMetricsWithoutDefinitionGetNoField() throws {
        let bike = try realTest(.bike, "threshold_30min")

        let onlyHeartRate = bike.resultInputs(definitions: [.thresholdHeartRate])
        // Weiter optional: Der Test ermittelt zwei Werte.
        XCTAssertEqual(onlyHeartRate.map(\.id), ["threshold_heart_rate"])
        XCTAssertEqual(onlyHeartRate.map(\.isOptional), [true])

        XCTAssertTrue(bike.resultInputs(definitions: []).isEmpty)
        XCTAssertTrue(bike.evaluate(["threshold_heart_rate": 160], definitions: []).isEmpty)
    }

    // MARK: - Direkte Auswertung

    func testBikeThresholdTestTakesHeartRateAndPower() throws {
        let bike = try realTest(.bike, "threshold_30min")
        let defs = try definitions(.bike)

        let both = bike.evaluate(["threshold_heart_rate": 162, "threshold_power": 245], definitions: defs)
        let expectedBoth: [PerformanceMetric: Double] = [.thresholdHeartRate: 162, .thresholdPower: 245]
        XCTAssertEqual(both, expectedBoth)

        // Ohne Leistungsmesser reicht der Puls.
        let heartRateOnly = bike.evaluate(["threshold_heart_rate": 158], definitions: defs)
        let expectedHeartRate: [PerformanceMetric: Double] = [.thresholdHeartRate: 158]
        XCTAssertEqual(heartRateOnly, expectedHeartRate)

        let powerOnly = bike.evaluate(["threshold_power": 230], definitions: defs)
        let expectedPower: [PerformanceMetric: Double] = [.thresholdPower: 230]
        XCTAssertEqual(powerOnly, expectedPower)

        XCTAssertTrue(bike.evaluate([:], definitions: defs).isEmpty)
    }

    func testDirectValuesOutsideTheirRangeOrNotFiniteAreDropped() throws {
        let bike = try realTest(.bike, "threshold_30min")
        let defs = try definitions(.bike)

        // Puls unter 100 fällt weg, die Leistung bleibt.
        let lowHeartRate = bike.evaluate(["threshold_heart_rate": 90, "threshold_power": 250], definitions: defs)
        let expected: [PerformanceMetric: Double] = [.thresholdPower: 250]
        XCTAssertEqual(lowHeartRate, expected)

        XCTAssertTrue(bike.evaluate(["threshold_power": 601], definitions: defs).isEmpty)
        XCTAssertTrue(bike.evaluate(["threshold_heart_rate": Double.nan], definitions: defs).isEmpty)
        // Grenzen gehören dazu.
        let bounds = bike.evaluate(["threshold_heart_rate": 100, "threshold_power": 600], definitions: defs)
        let expectedBounds: [PerformanceMetric: Double] = [.thresholdHeartRate: 100, .thresholdPower: 600]
        XCTAssertEqual(bounds, expectedBounds)
    }

    func testDirectEvaluationIgnoresUnknownEntries() throws {
        let bike = try realTest(.bike, "threshold_30min")

        let result = bike.evaluate(["threshold_heart_rate": 160, "cadence": 90, "time_400m": 360], definitions: try definitions(.bike))

        let expected: [PerformanceMetric: Double] = [.thresholdHeartRate: 160]
        XCTAssertEqual(result, expected)
    }

    func testInfiniteValuesAreDroppedEvenInAnOpenRange() {
        let open = TestInput(id: "threshold_power", label: "Leistung", unit: "W", range: 1...Double.infinity)
        let test = customTest(produces: [.thresholdPower], inputs: [open], evaluation: .direct)

        XCTAssertTrue(test.evaluate(["threshold_power": Double.infinity], definitions: []).isEmpty)
        let expected: [PerformanceMetric: Double] = [.thresholdPower: 5000]
        XCTAssertEqual(test.evaluate(["threshold_power": 5000], definitions: []), expected)
    }

    func testDirectValuesAreTakenAsEnteredWithoutRounding() {
        let power = TestInput(id: "threshold_power", label: "Leistung", unit: "W", range: 50...600)
        let test = customTest(produces: [.thresholdPower], inputs: [power], evaluation: .direct)

        let expected: [PerformanceMetric: Double] = [.thresholdPower: 280.37]
        XCTAssertEqual(test.evaluate(["threshold_power": 280.37], definitions: []), expected)
    }

    func testDirectEvaluationNeedsAnInputWithTheMetricsID() {
        // Eine eigene Eingabe mit anderer Kennung ergibt bei direkter Auswertung keinen Wert.
        let test = customTest(produces: [.thresholdPower], inputs: [timeA], evaluation: .direct)

        XCTAssertTrue(test.evaluate(["time_a": 300, "threshold_power": 250], definitions: [.thresholdPower]).isEmpty)
    }

    func testRunThresholdTestTakesHeartRateAndPace() throws {
        let threshold = try realTest(.run, "threshold_30min")

        let result = threshold.evaluate(["threshold_heart_rate": 171, "threshold_pace_per_km": 290], definitions: try definitions(.run))

        let expected: [PerformanceMetric: Double] = [.thresholdHeartRate: 171, .thresholdPacePerKilometer: 290]
        XCTAssertEqual(result, expected)
        XCTAssertEqual(threshold.resultSource, .tested)
    }

    func testEntryTestIsNotAMaximalEffortAndOnlyGivesAnEstimate() throws {
        let entry = try realTest(.run, "entry_easy_25min")

        XCTAssertFalse(entry.maximalEffort)
        XCTAssertEqual(entry.resultSource, .estimated)
        XCTAssertEqual(entry.produces, [PerformanceMetric.thresholdPacePerKilometer])
        let result = entry.evaluate(["threshold_pace_per_km": 360], definitions: try definitions(.run))
        let expected: [PerformanceMetric: Double] = [.thresholdPacePerKilometer: 360]
        XCTAssertEqual(result, expected)
        XCTAssertTrue(entry.evaluate(["threshold_pace_per_km": 100], definitions: try definitions(.run)).isEmpty)
    }

    // MARK: - Critical Swim Speed

    func testCriticalSwimPaceIsHalfTheDifferenceOfTheTwoTimes() throws {
        let css = try realTest(.swim, "css_400_200")

        // 400 m in 6:00, 200 m in 2:50: (360 − 170) / 2 = 95 s pro 100 m.
        let result = css.evaluate(["time_400m": 360, "time_200m": 170], definitions: try definitions(.swim))

        let expected: [PerformanceMetric: Double] = [.criticalSwimPace: 95.0]
        XCTAssertEqual(result, expected)
        XCTAssertEqual(css.resultSource, .tested)
    }

    func testCriticalSwimPaceIsRoundedToTenths() throws {
        let css = try realTest(.swim, "css_400_200")

        // (361 − 170,33) / 2 = 95,335 → 95,3.
        let result = css.evaluate(["time_400m": 361, "time_200m": 170.33], definitions: try definitions(.swim))

        let expected: [PerformanceMetric: Double] = [.criticalSwimPace: 95.3]
        XCTAssertEqual(result, expected)
    }

    func testCriticalSwimPaceNeedsALongDistanceSlowerThanTheShortOne() throws {
        let css = try realTest(.swim, "css_400_200")
        let defs = try definitions(.swim)

        XCTAssertTrue(css.evaluate(["time_400m": 300, "time_200m": 300], definitions: defs).isEmpty)
        XCTAssertTrue(css.evaluate(["time_400m": 200, "time_200m": 250], definitions: defs).isEmpty)
    }

    func testCriticalSwimPaceNeedsBothTimes() throws {
        let css = try realTest(.swim, "css_400_200")
        let defs = try definitions(.swim)

        XCTAssertTrue(css.evaluate(["time_400m": 360], definitions: defs).isEmpty)
        XCTAssertTrue(css.evaluate(["time_200m": 170], definitions: defs).isEmpty)
        XCTAssertTrue(css.evaluate([:], definitions: defs).isEmpty)
    }

    func testCriticalSwimPaceIgnoresTimesOutsideTheirRange() throws {
        let css = try realTest(.swim, "css_400_200")
        let defs = try definitions(.swim)

        // 400 m erlaubt 180 bis 1500 s, 200 m erlaubt 80 bis 750 s.
        XCTAssertTrue(css.evaluate(["time_400m": 1600, "time_200m": 170], definitions: defs).isEmpty)
        XCTAssertTrue(css.evaluate(["time_400m": 360, "time_200m": 79], definitions: defs).isEmpty)
        XCTAssertTrue(css.evaluate(["time_400m": Double.infinity, "time_200m": 170], definitions: defs).isEmpty)
        // Die Grenzen selbst gehören dazu: (180 − 80) / 2 = 50.
        let expected: [PerformanceMetric: Double] = [.criticalSwimPace: 50]
        XCTAssertEqual(css.evaluate(["time_400m": 180, "time_200m": 80], definitions: defs), expected)
    }

    func testCriticalSwimPaceNeedsTheLongerDistanceFirstAndAProducedMetric() {
        let reversed = customTest(
            produces: [.criticalSwimPace], inputs: [timeA, timeB],
            evaluation: .criticalSwimPace(longInput: "time_a", longMeters: 200, shortInput: "time_b", shortMeters: 400)
        )
        XCTAssertTrue(reversed.evaluate(["time_a": 360, "time_b": 170], definitions: []).isEmpty)

        let sameDistance = customTest(
            produces: [.criticalSwimPace], inputs: [timeA, timeB],
            evaluation: .criticalSwimPace(longInput: "time_a", longMeters: 400, shortInput: "time_b", shortMeters: 400)
        )
        XCTAssertTrue(sameDistance.evaluate(["time_a": 360, "time_b": 170], definitions: []).isEmpty)

        let nothingProduced = customTest(
            produces: [], inputs: [timeA, timeB],
            evaluation: .criticalSwimPace(longInput: "time_a", longMeters: 400, shortInput: "time_b", shortMeters: 200)
        )
        XCTAssertTrue(nothingProduced.evaluate(["time_a": 360, "time_b": 170], definitions: []).isEmpty)

        // Gleicher Aufbau mit Ergebnis: 800 m und 400 m, (720 − 340) / 4 = 95.
        let longer = customTest(
            produces: [.criticalSwimPace], inputs: [timeA, timeB],
            evaluation: .criticalSwimPace(longInput: "time_a", longMeters: 800, shortInput: "time_b", shortMeters: 400)
        )
        let expected: [PerformanceMetric: Double] = [.criticalSwimPace: 95]
        XCTAssertEqual(longer.evaluate(["time_a": 720, "time_b": 340], definitions: []), expected)
    }

    // MARK: - Pace pro 100 m

    func testTimeTrialGivesThePacePerHundredMeters() throws {
        let timeTrial = try realTest(.swim, "time_trial_1000m")

        // 1000 m in 25:00 = 1500 s: 150 s pro 100 m.
        let result = timeTrial.evaluate(["time_1000m": 1500], definitions: try definitions(.swim))

        let expected: [PerformanceMetric: Double] = [.criticalSwimPace: 150.0]
        XCTAssertEqual(result, expected)
        XCTAssertEqual(timeTrial.resultSource, .tested)
    }

    func testPacePerHundredMetersIsRoundedToTenths() throws {
        let timeTrial = try realTest(.swim, "time_trial_1000m")

        // 1234,56 s / 10 = 123,456 → 123,5.
        let result = timeTrial.evaluate(["time_1000m": 1234.56], definitions: try definitions(.swim))

        let expected: [PerformanceMetric: Double] = [.criticalSwimPace: 123.5]
        XCTAssertEqual(result, expected)
    }

    func testPacePerHundredMetersNeedsAValidTime() throws {
        let timeTrial = try realTest(.swim, "time_trial_1000m")
        let defs = try definitions(.swim)

        XCTAssertTrue(timeTrial.evaluate([:], definitions: defs).isEmpty)
        XCTAssertTrue(timeTrial.evaluate(["time_1000m": 599], definitions: defs).isEmpty)
        XCTAssertTrue(timeTrial.evaluate(["time_1000m": 3001], definitions: defs).isEmpty)
        XCTAssertTrue(timeTrial.evaluate(["time_1000m": -Double.infinity], definitions: defs).isEmpty)
        XCTAssertTrue(timeTrial.evaluate(["time_400m": 360], definitions: defs).isEmpty)
    }

    func testPacePerHundredMetersNeedsADistanceAndAProducedMetric() {
        let noDistance = customTest(produces: [.criticalSwimPace], inputs: [timeA], evaluation: .pacePerHundredMeters(input: "time_a", meters: 0))
        XCTAssertTrue(noDistance.evaluate(["time_a": 300], definitions: []).isEmpty)

        let negativeDistance = customTest(produces: [.criticalSwimPace], inputs: [timeA], evaluation: .pacePerHundredMeters(input: "time_a", meters: -400))
        XCTAssertTrue(negativeDistance.evaluate(["time_a": 300], definitions: []).isEmpty)

        let nothingProduced = customTest(produces: [], inputs: [timeA], evaluation: .pacePerHundredMeters(input: "time_a", meters: 400))
        XCTAssertTrue(nothingProduced.evaluate(["time_a": 300], definitions: []).isEmpty)

        // 400 m in 5:00: 75 s pro 100 m.
        let valid = customTest(produces: [.criticalSwimPace], inputs: [timeA], evaluation: .pacePerHundredMeters(input: "time_a", meters: 400))
        let expected: [PerformanceMetric: Double] = [.criticalSwimPace: 75]
        XCTAssertEqual(valid.evaluate(["time_a": 300], definitions: []), expected)
    }

    // MARK: - Alle echten Tests

    func testEveryRealTestGivesPlausibleValuesForTypicalResults() throws {
        // Typische Ergebnisse je Eingabe: Jeder Test der echten Sportarten ergibt Werte im plausiblen Bereich.
        let typical: [String: Double] = [
            "time_400m": 400, "time_200m": 190, "time_1000m": 1100,
            "threshold_heart_rate": 165, "threshold_power": 220, "threshold_pace_per_km": 300
        ]
        for module in SportRegistry.standard.modules {
            let defs = module.performanceMetrics
            for test in module.performanceTests {
                let result = test.evaluate(typical, definitions: defs)
                XCTAssertEqual(Set(result.keys), Set(test.produces), "\(module.id) \(test.id)")
                for (metric, value) in result {
                    let found: PerformanceMetricDefinition? = defs.first(where: { (item: PerformanceMetricDefinition) -> Bool in item.metric == metric })
                    let definition = try XCTUnwrap(found, "\(module.id) \(metric)")
                    XCTAssertTrue(definition.plausibleRange.contains(value), "\(module.id) \(test.id) \(metric) \(value)")
                }
            }
        }
    }
}
