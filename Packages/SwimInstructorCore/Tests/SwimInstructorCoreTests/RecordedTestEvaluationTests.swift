import XCTest
@testable import SwimInstructorCore

/// Auswertung von Leistungstests aus der Aufzeichnung der Watch, mit simulierten Zeitreihen: Bahnen im Becken, Strecke,
/// Puls und Leistung laufen Sekunde für Sekunde durch die Fortschritts-Engine wie auf der Uhr.
final class RecordedTestEvaluationTests: XCTestCase {
    // MARK: - Hilfen

    private func test(_ sport: SportID, _ id: String) throws -> PerformanceTest {
        let module = try XCTUnwrap(SportRegistry.standard.module(for: sport))
        return try XCTUnwrap(module.performanceTests.first(where: { $0.id == id }), "\(sport) \(id)")
    }

    private func definitions(_ sport: SportID) throws -> [PerformanceMetricDefinition] {
        try XCTUnwrap(SportRegistry.standard.module(for: sport)).performanceMetrics
    }

    /// Ein Schritt nach Strecke mit gefühlter Anstrengung, wie ihn die Server-Module für Tests planen.
    private static func swim(_ name: String, _ meters: Int, effort: Double, rest: Int = 0) -> PlanStep {
        PlanStep(
            name: name, repetitions: 1, measure: .distance, distanceMeters: meters,
            targetType: .perceivedEffort, targetValue: effort, restSeconds: rest
        )
    }

    /// Ein Schritt nach Zeit mit gefühlter Anstrengung.
    private static func timed(_ name: String, _ seconds: Int, effort: Double) -> PlanStep {
        PlanStep(name: name, repetitions: 1, measure: .duration, durationSeconds: seconds, targetType: .perceivedEffort, targetValue: effort)
    }

    /// CSS-Test wie vom Server: einschwimmen, 400 m voll, 10 min Pause, 200 m voll, ausschwimmen.
    private static let cssSteps = [
        swim("Einschwimmen", 300, effort: 3),
        swim("Test 400 m", 400, effort: 10, rest: 600),
        swim("Test 200 m", 200, effort: 10),
        swim("Ausschwimmen", 200, effort: 2)
    ]

    /// 30-Minuten-Test: einlaufen bzw. einfahren, 30 min voll, auslaufen.
    private static let thresholdSteps = [
        timed("Einlaufen", 900, effort: 3),
        timed("Test 30 Minuten", 1800, effort: 10),
        timed("Auslaufen", 600, effort: 2)
    ]

    /// `count` Bahnen ab `start`, jede `seconds` lang, ohne Pause dazwischen.
    private func laps(_ count: Int, from start: TimeInterval, each seconds: TimeInterval) -> [LapTime] {
        (0..<count).map { LapTime(start: start + Double($0) * seconds, end: start + Double($0 + 1) * seconds) }
    }

    /// Im Becken: Die Uhr meldet jede Sekunde die Strecke aus den beendeten Bahnen. Endet die Aufzeichnung bei `finishAt`
    /// (sonst kurz nach der letzten Bahn).
    private func pool(_ laps: [LapTime], lapLength: Int = 25, steps: [PlanStep] = RecordedTestEvaluationTests.cssSteps, finishAt: Int? = nil) -> WorkoutRecording {
        var progress = SessionProgress(steps: steps)
        var recording = WorkoutRecording(lapLengthMeters: lapLength)
        let end = finishAt ?? Int(laps.last?.end ?? 0) + 1
        var meters = 0.0
        for second in 0...end {
            let done = laps.filter { $0.end <= TimeInterval(second) }
            for lap in done {
                recording.recordLap(start: lap.start, end: lap.end)
            }
            meters = Double(done.count * lapLength)
            progress.update(meters: meters, elapsed: TimeInterval(second))
        }
        progress.finish(meters: meters, elapsed: TimeInterval(end))
        recording.segments = progress.segments
        return recording
    }

    /// Draußen oder auf der Rolle: jede Sekunde Strecke (Tempo `speed` in dieser Sekunde) und Leistung, alle fünf Sekunden
    /// Puls. `nil` heißt: kein Wert in dieser Sekunde.
    private func continuous(
        until end: Int,
        steps: [PlanStep] = RecordedTestEvaluationTests.thresholdSteps,
        speed: (Int) -> Double,
        heartRate: (Int) -> Double?,
        power: (Int) -> Double? = { _ in nil }
    ) -> WorkoutRecording {
        var progress = SessionProgress(steps: steps)
        var recording = WorkoutRecording()
        var meters = 0.0
        for second in 0...end {
            if second > 0 { meters += speed(second) }
            let elapsed = TimeInterval(second)
            recording.recordDistance(meters, at: elapsed)
            if second % 5 == 0, let beats = heartRate(second) {
                recording.recordHeartRate(beats, at: elapsed)
            }
            if let watts = power(second) {
                recording.recordPower(watts, at: elapsed)
            }
            progress.update(meters: meters, elapsed: elapsed)
        }
        progress.finish(meters: meters, elapsed: TimeInterval(end))
        recording.segments = progress.segments
        return recording
    }

    /// Ein Abschnitt ohne Engine, für die Grenzfälle der Rechnung.
    private func segment(_ step: PlanStep, index: Int, start: TimeInterval, seconds: TimeInterval, meters: Double, reached: Bool = true) -> RecordedSegment {
        let target: ProgressUnit.Target? = step.distanceMeters.map { ProgressUnit.Target.meters(Double($0)) }
            ?? step.durationSeconds.map { ProgressUnit.Target.seconds(TimeInterval($0)) }
        let unit = ProgressUnit(index: index, stepIndex: index, step: step, repetition: 1, target: target, restSeconds: 0)
        return RecordedSegment(unit: unit, startElapsed: start, endElapsed: start + seconds, meters: meters, reachedTarget: reached)
    }

    /// Ein ganzer CSS-Test im 25-m-Becken mit allem, was im Wasser vorkommt.
    private var cssSwim: [LapTime] {
        laps(12, from: 0, each: 30)             // Einschwimmen bis 6:00
            + laps(16, from: 420, each: 20)     // eine Minute am Rand, dann 400 m in 5:20
            + laps(2, from: 740, each: 40)      // zwei lockere Bahnen in der Pause
            + laps(8, from: 1350, each: 18)     // 10 s nach dem Ende der Pause los, 200 m in 2:24
            + laps(8, from: 1494, each: 30)     // ausschwimmen
    }

    // MARK: - Testbelastung

    func testOnlyStepsWithPerceivedEffortFromNineAreTestEffort() {
        func step(_ target: StepTarget?, _ value: Double?) -> PlanStep {
            PlanStep(name: "x", repetitions: 1, measure: .distance, distanceMeters: 400, targetType: target, targetValue: value)
        }
        XCTAssertTrue(step(.perceivedEffort, 9).isTestEffort)
        XCTAssertTrue(step(.perceivedEffort, 10).isTestEffort)
        XCTAssertFalse(step(.perceivedEffort, 8).isTestEffort)
        XCTAssertFalse(step(.perceivedEffort, nil).isTestEffort)
        XCTAssertFalse(step(.heartRateZone, 10).isTestEffort)
        XCTAssertFalse(step(nil, nil).isTestEffort)
    }

    func testModulesDescribeWhatTheWatchRecords() throws {
        XCTAssertEqual(try test(.swim, "css_400_200").recorded, [
            .segmentTime(input: "time_400m", meters: 400), .segmentTime(input: "time_200m", meters: 200)
        ])
        XCTAssertEqual(try test(.swim, "time_trial_1000m").recorded, [.segmentTime(input: "time_1000m", meters: 1000)])
        XCTAssertEqual(try test(.run, "threshold_30min").recorded, [
            .average(input: "threshold_heart_rate", signal: .heartRate, lastSeconds: 1200),
            .average(input: "threshold_pace_per_km", signal: .pacePerKilometer, lastSeconds: 1200)
        ])
        XCTAssertEqual(try test(.bike, "threshold_30min").recorded, [
            .average(input: "threshold_heart_rate", signal: .heartRate, lastSeconds: 1200),
            .average(input: "threshold_power", signal: .power, lastSeconds: nil)
        ])
        XCTAssertTrue(try test(.run, "entry_easy_25min").recorded.isEmpty)
        // Jede Eingabe, die die Watch misst, gibt es auch beim Eintragen von Hand.
        for module in SportRegistry.standard.modules {
            for test in module.performanceTests {
                let inputs = test.resultInputs(definitions: module.performanceMetrics).map(\.id)
                for measurement in test.recorded {
                    XCTAssertTrue(inputs.contains(measurement.input), "\(module.id) \(test.id) \(measurement.input)")
                }
            }
        }
    }

    // MARK: - CSS aus Bahnzeiten

    func testCSSComesFromLapTimesWithoutWaitingAtTheWallOrRecoveryLaps() throws {
        let recording = pool(cssSwim)

        // Die Abschnitte der Engine enthalten das Warten am Rand bzw. den späten Start nach der Pause.
        let tests = recording.segments.filter { $0.unit.step.isTestEffort }
        XCTAssertEqual(tests.map(\.duration), [380, 154])
        XCTAssertTrue(tests.allSatisfy(\.reachedTarget))

        let result = try test(.swim, "css_400_200").evaluate(recording: recording, definitions: try definitions(.swim))

        // Die Bahnen zählen: 400 m in 5:20, 200 m in 2:24, CSS (320 − 144) / 2.
        XCTAssertEqual(result.entries, ["time_400m": 320, "time_200m": 144])
        XCTAssertEqual(result.values, [.criticalSwimPace: 88])
        XCTAssertEqual(result.problems, [])
        XCTAssertTrue(result.isValid)
    }

    func testWithoutUsableLapsTheSegmentTimeCounts() throws {
        let css = try test(.swim, "css_400_200")
        let definitions = try definitions(.swim)
        var recording = pool(cssSwim)

        // Freiwasser: keine Bahnlänge.
        recording.lapLengthMeters = nil
        XCTAssertEqual(css.evaluate(recording: recording, definitions: definitions).entries, ["time_400m": 380, "time_200m": 154])

        // Becken, dessen Länge nicht in der Teststrecke aufgeht.
        recording.lapLengthMeters = 33
        XCTAssertEqual(css.evaluate(recording: recording, definitions: definitions).entries, ["time_400m": 380, "time_200m": 154])

        // Becken ohne Bahnen (Runden-Ereignisse fehlen).
        let withoutLaps = WorkoutRecording(lapLengthMeters: 25, segments: recording.segments)
        let result = css.evaluate(recording: withoutLaps, definitions: definitions)
        XCTAssertEqual(result.entries, ["time_400m": 380, "time_200m": 154])
        XCTAssertEqual(result.values, [.criticalSwimPace: 113])
    }

    func testThousandMetersInAFiftyMeterPool() throws {
        let steps = [swim("Einschwimmen", 400, effort: 3), swim("Test 1000 m", 1000, effort: 10), swim("Ausschwimmen", 200, effort: 2)]
        let swum = laps(8, from: 0, each: 40) + laps(20, from: 350, each: 40) + laps(4, from: 1150, each: 50)

        let recording = pool(swum, lapLength: 50, steps: steps)
        let result = try test(.swim, "time_trial_1000m").evaluate(recording: recording, definitions: try definitions(.swim))

        XCTAssertEqual(result.entries, ["time_1000m": 800])
        XCTAssertEqual(result.values, [.criticalSwimPace: 80])
        XCTAssertEqual(result.problems, [])
    }

    func testAnAbortedTwoHundredIsRejectedWithReason() throws {
        let swum = laps(12, from: 0, each: 30) + laps(16, from: 420, each: 20) + laps(4, from: 1350, each: 18)

        let recording = pool(swum, finishAt: 1430)
        let result = try test(.swim, "css_400_200").evaluate(recording: recording, definitions: try definitions(.swim))

        XCTAssertEqual(result.entries, ["time_400m": 320])
        XCTAssertEqual(result.values, [:])
        XCTAssertEqual(result.problems, ["Test über 200 m vorzeitig beendet (100 m geschafft)."])
        XCTAssertFalse(result.isValid)
    }

    func testAMissingTwoHundredIsRejectedWithReason() throws {
        let swum = laps(12, from: 0, each: 30) + laps(16, from: 420, each: 20)

        // Beendet in der Pause nach den 400 m.
        let recording = pool(swum, finishAt: 1000)
        let result = try test(.swim, "css_400_200").evaluate(recording: recording, definitions: try definitions(.swim))

        XCTAssertEqual(result.entries, ["time_400m": 320])
        XCTAssertEqual(result.problems, ["Die 200 m des Tests fehlen in der Aufzeichnung: Die Einheit endete vorher."])
        XCTAssertFalse(result.isValid)
    }

    func testTimesThatGiveNoCSSFallBackToAGeneralReason() throws {
        let long = segment(Self.cssSteps[1], index: 1, start: 0, seconds: 200, meters: 400)
        let short = segment(Self.cssSteps[2], index: 2, start: 800, seconds: 210, meters: 200)

        let result = try test(.swim, "css_400_200").evaluate(recording: WorkoutRecording(segments: [long, short]), definitions: try definitions(.swim))

        // Beide Zeiten liegen im Bereich, aber die 200 m sind nicht schneller als die 400 m.
        XCTAssertEqual(result.entries, ["time_400m": 200, "time_200m": 210])
        XCTAssertEqual(result.values, [:])
        XCTAssertEqual(result.problems, ["Aus der Aufzeichnung ergibt sich kein gültiger Wert."])
    }

    func testTimesOutsideThePlausibleRangeAreNamed() throws {
        let long = segment(Self.cssSteps[1], index: 1, start: 0, seconds: 120, meters: 400)
        let short = segment(Self.cssSteps[2], index: 2, start: 800, seconds: 60, meters: 200)

        let result = try test(.swim, "css_400_200").evaluate(recording: WorkoutRecording(segments: [long, short]), definitions: try definitions(.swim))

        XCTAssertEqual(result.values, [:])
        XCTAssertEqual(result.problems, [
            "Zeit 400 m liegt mit 2:00 min außerhalb des Plausiblen.",
            "Zeit 200 m liegt mit 1:00 min außerhalb des Plausiblen."
        ])
    }

    // MARK: - Laufen: Schwellenpuls und Tempo aus den letzten 20 Minuten

    /// 2,8 m/s beim Einlaufen, 3,6 m/s im Test, 2,5 m/s danach.
    private func runSpeed(_ second: Int) -> Double {
        second <= 900 ? 2.8 : second <= 2700 ? 3.6 : 2.5
    }

    /// Im Test erst 150, in den letzten 20 Minuten 170.
    private func runHeartRate(_ second: Int) -> Double? {
        second < 1500 ? 150 : second <= 2700 ? 170 : 140
    }

    func testRunThresholdUsesTheLastTwentyMinutes() throws {
        let recording = continuous(until: 3300, speed: runSpeed, heartRate: runHeartRate)

        let segment = try XCTUnwrap(recording.segments.first { $0.unit.step.isTestEffort })
        XCTAssertEqual(segment.startElapsed, 900)
        XCTAssertEqual(segment.endElapsed, 2700)

        let result = try test(.run, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.run))

        // 4320 m in 20 min: 4:38 pro km.
        XCTAssertEqual(result.entries, ["threshold_heart_rate": 170, "threshold_pace_per_km": 278])
        XCTAssertEqual(result.values, [.thresholdHeartRate: 170, .thresholdPacePerKilometer: 278])
        XCTAssertEqual(result.problems, [])
    }

    func testAHeartRateGapDiscardsOnlyTheHeartRate() throws {
        let recording = continuous(until: 3300, speed: runSpeed) { second in
            (2000..<2100).contains(second) && second != 2000 ? nil : self.runHeartRate(second)
        }

        let result = try test(.run, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.run))

        XCTAssertEqual(result.entries, ["threshold_pace_per_km": 278])
        XCTAssertEqual(result.values, [.thresholdPacePerKilometer: 278])
        XCTAssertEqual(result.problems, ["Schwellenpuls verworfen: 1:40 ohne Messung."])
        XCTAssertTrue(result.isValid)
    }

    func testAnAbortedThirtyMinuteTestIsRejectedOnce() throws {
        let recording = continuous(until: 2000, speed: runSpeed, heartRate: runHeartRate)

        let result = try test(.run, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.run))

        XCTAssertEqual(result.entries, [:])
        XCTAssertEqual(result.problems, ["Test nach 18:20 von 30:00 beendet."])
        XCTAssertFalse(result.isValid)
    }

    func testATestEndedBeforeItsStartIsMissing() throws {
        let recording = continuous(until: 600, speed: runSpeed, heartRate: runHeartRate)

        let result = try test(.run, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.run))

        XCTAssertEqual(result.problems, ["Der Testabschnitt fehlt in der Aufzeichnung: Die Einheit endete vorher."])
        XCTAssertFalse(result.isValid)
    }

    func testSkippingTheTestByHandCountsAsAborted() throws {
        var progress = SessionProgress(steps: Self.thresholdSteps)
        var recording = WorkoutRecording()
        for second in 0...1200 {
            recording.recordHeartRate(165, at: TimeInterval(second))
            progress.update(meters: Double(second) * 3, elapsed: TimeInterval(second))
        }
        progress.move(.next, meters: 3600, elapsed: 1200)
        recording.segments = progress.segments

        let result = try test(.run, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.run))

        XCTAssertEqual(result.problems, ["Test nach 5:00 von 30:00 beendet."])
    }

    func testOnATreadmillWithoutDistanceOnlyTheHeartRateCounts() throws {
        let recording = continuous(until: 3300, speed: { _ in 0 }, heartRate: runHeartRate)

        let result = try test(.run, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.run))

        XCTAssertEqual(result.values, [.thresholdHeartRate: 170])
        XCTAssertEqual(result.problems, ["Schwellentempo verworfen: keine Strecke gemessen."])
    }

    func testWithoutHeartRateTheHeartRateIsMissingWithReason() throws {
        let recording = continuous(until: 3300, speed: runSpeed) { _ in nil }

        let result = try test(.run, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.run))

        XCTAssertEqual(result.values, [.thresholdPacePerKilometer: 278])
        XCTAssertEqual(result.problems, ["Schwellenpuls: nichts gemessen."])
    }

    func testAnImplausibleHeartRateIsNamedAndLeftOut() throws {
        let recording = continuous(until: 3300, speed: runSpeed) { _ in 230 }

        let result = try test(.run, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.run))

        XCTAssertEqual(result.entries["threshold_heart_rate"], 230)
        XCTAssertEqual(result.values, [.thresholdPacePerKilometer: 278])
        XCTAssertEqual(result.problems, ["Schwellenpuls liegt mit 230 bpm außerhalb des Plausiblen."])
    }

    // MARK: - Rad: Leistung nur mit Leistungsmesser

    func testBikeThresholdWithPowerMeter() throws {
        let recording = continuous(until: 3300, speed: { _ in 8 }, heartRate: { _ in 160 }) { second in
            second <= 900 ? 150 : second <= 2700 ? 220 : 120
        }

        let result = try test(.bike, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.bike))

        // Leistung über die ganzen 30 Minuten, ab dem Start des Tests.
        XCTAssertEqual(result.values[.thresholdHeartRate], 160)
        XCTAssertEqual(try XCTUnwrap(result.values[.thresholdPower]), 220, accuracy: 0.5)
        XCTAssertEqual(result.problems, [])
    }

    func testBikeWithoutPowerMeterGivesHeartRateWithoutComplaint() throws {
        let recording = continuous(until: 3300, speed: { _ in 8 }, heartRate: { _ in 160 })

        let result = try test(.bike, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.bike))

        XCTAssertEqual(result.entries, ["threshold_heart_rate": 160])
        XCTAssertEqual(result.values, [.thresholdHeartRate: 160])
        XCTAssertEqual(result.problems, [])
    }

    func testAPowerGapDiscardsThePower() throws {
        let recording = continuous(until: 3300, speed: { _ in 8 }, heartRate: { _ in 160 }) { second in
            (1001..<1120).contains(second) ? nil : 220
        }

        let result = try test(.bike, "threshold_30min").evaluate(recording: recording, definitions: try definitions(.bike))

        XCTAssertEqual(result.values, [.thresholdHeartRate: 160])
        XCTAssertEqual(result.problems, ["Schwellenleistung (FTP) verworfen: 2:00 ohne Messung."])
    }

    // MARK: - Tests, die die Watch nicht auswertet

    func testATestWithoutFullEffortChangesNothing() throws {
        let entry = try test(.run, "entry_easy_25min")
        let recording = continuous(until: 3300, speed: runSpeed, heartRate: runHeartRate)

        let result = entry.evaluate(recording: recording, definitions: try definitions(.run))

        XCTAssertEqual(result.problems, [entry.resultHint])
        XCTAssertFalse(result.isValid)

        let withoutHint = PerformanceTest(id: "easy", displayName: "Locker", produces: [.thresholdHeartRate], maximalEffort: false, durationMinutes: 20)
        XCTAssertEqual(withoutHint.evaluate(recording: recording, definitions: []).problems, ["Dieser Test ändert dein Profil nicht."])
    }

    func testATestWithoutRecordedMeasurementsIsEnteredOnThePhone() throws {
        let rowing = try XCTUnwrap(RowingTestModule().performanceTests.first)

        let result = rowing.evaluate(recording: WorkoutRecording(), definitions: RowingTestModule().performanceMetrics)

        XCTAssertEqual(result.problems, ["Diesen Test wertet die Watch nicht aus. Trag das Ergebnis auf dem iPhone ein."])
        XCTAssertEqual(result.entries, [:])
    }

    func testAMeasurementWithoutMatchingInputIsNamedByItsKey() throws {
        let custom = PerformanceTest(
            id: "custom", displayName: "Eigener Test", produces: [.thresholdHeartRate], maximalEffort: true, durationMinutes: 30,
            recorded: [.average(input: "lactate_heart_rate", signal: .heartRate, lastSeconds: nil)]
        )
        let recording = continuous(until: 3300, speed: runSpeed) { _ in nil }

        let result = custom.evaluate(recording: recording, definitions: try definitions(.run))

        XCTAssertEqual(result.problems, ["lactate_heart_rate: nichts gemessen."])
    }
}
