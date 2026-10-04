import XCTest
@testable import SwimInstructorCore

/// Die Fortschritts-Engine der Watch mit simulierten Zeitreihen: Strecke und Laufzeit kommen wie von der Uhr.
final class SessionProgressTests: XCTestCase {
    // MARK: - Hilfen

    private static func timed(_ name: String, _ seconds: Int, repetitions: Int = 1, rest: Int = 0) -> PlanStep {
        PlanStep(name: name, repetitions: repetitions, measure: .duration, durationSeconds: seconds, restSeconds: rest, cue: name)
    }

    private static func distance(_ name: String, _ meters: Int, repetitions: Int = 1, rest: Int = 0) -> PlanStep {
        PlanStep(name: name, repetitions: repetitions, measure: .distance, distanceMeters: meters, restSeconds: rest)
    }

    /// Intervalllauf: 10 min einlaufen, 6 × 3 min mit 90 s Pause, 5 min auslaufen.
    private static let intervals = [timed("Einlaufen", 600), timed("Intervall", 180, repetitions: 6, rest: 90), timed("Auslaufen", 300)]

    /// Jede Sekunde eine Meldung mit `metersPerSecond`; liefert die Ereignisse mit ihrer Sekunde.
    @discardableResult
    private func run(
        _ progress: inout SessionProgress,
        from start: Int,
        through end: Int,
        metersPerSecond: Double = 3
    ) -> [(second: Int, event: ProgressEvent)] {
        var events: [(second: Int, event: ProgressEvent)] = []
        for second in start...end {
            for event in progress.update(meters: Double(second) * metersPerSecond, elapsed: TimeInterval(second)) {
                events.append((second: second, event: event))
            }
        }
        return events
    }

    private func isRest(_ event: ProgressEvent) -> Bool {
        if case .restStarted = event { return true }
        return false
    }

    private func started(_ events: [(second: Int, event: ProgressEvent)]) -> [(second: Int, name: String, repetition: Int)] {
        events.compactMap { entry in
            guard case let .workStarted(unit) = entry.event else { return nil }
            return (second: entry.second, name: unit.step.name, repetition: unit.repetition)
        }
    }

    // MARK: - Wiederholungen nach Zeit

    func testIntervalSwitchesAfterThreeMinutesAndRestCounts() {
        var progress = SessionProgress(steps: Self.intervals)
        XCTAssertEqual(progress.units.count, 8)
        XCTAssertEqual(progress.stepCount, 3)

        let events = run(&progress, from: 0, through: 3000)
        let starts = started(events)

        // Nach 10 min Einlaufen das erste Intervall, jedes nach 3:00 Arbeit und 1:30 Pause.
        XCTAssertEqual(starts.first?.second, 600)
        XCTAssertEqual(starts.filter { $0.name == "Intervall" }.map(\.second), [600, 870, 1140, 1410, 1680, 1950])
        // Nach dem letzten Intervall auch die Pause, dann 5 min Auslaufen.
        XCTAssertEqual(starts.last?.name, "Auslaufen")
        XCTAssertEqual(starts.last?.second, 2220)
        XCTAssertEqual(events.last?.second, 2520)
        XCTAssertEqual(events.last?.event, .completed)
        XCTAssertTrue(progress.isCompleted)
        XCTAssertNil(progress.current)

        let rests = events.filter { isRest($0.event) }.map(\.second)
        XCTAssertEqual(rests, [780, 1050, 1320, 1590, 1860, 2130])

        XCTAssertEqual(progress.segments.count, 8)
        XCTAssertTrue(progress.segments.allSatisfy(\.reachedTarget))
        XCTAssertEqual(progress.segments.filter { $0.unit.step.name == "Intervall" }.map(\.duration), Array(repeating: 180, count: 6))
        XCTAssertEqual(progress.segments[1].startElapsed, 600)
        XCTAssertEqual(progress.segments[1].meters, 540)
    }

    func testStatusCountsDownWorkAndRest() {
        var progress = SessionProgress(steps: Self.intervals)
        run(&progress, from: 0, through: 700)

        guard case let .work(unit, done, remaining) = progress.status(meters: 2100, elapsed: 700) else {
            return XCTFail("Intervall erwartet")
        }
        XCTAssertEqual(unit.step.name, "Intervall")
        XCTAssertEqual(unit.repetition, 1)
        XCTAssertEqual(done, 100)
        XCTAssertEqual(remaining, 80)

        run(&progress, from: 701, through: 800)
        guard case let .rest(after, next, seconds) = progress.status(meters: 2400, elapsed: 800) else {
            return XCTFail("Pause erwartet")
        }
        XCTAssertEqual(after.repetition, 1)
        XCTAssertEqual(next?.repetition, 2)
        XCTAssertEqual(seconds, 70)
        // Zwischen zwei Meldungen rundet die Pause auf.
        guard case let .rest(_, _, rounded) = progress.status(meters: 2400, elapsed: 800.4) else { return XCTFail("Pause erwartet") }
        XCTAssertEqual(rounded, 70)
    }

    func testSparseSamplesStillEndEveryUnitOnTime() {
        var progress = SessionProgress(steps: [Self.timed("Block", 100, repetitions: 3)])
        progress.update(meters: 0, elapsed: 0)

        let events = progress.update(meters: 1000, elapsed: 500)

        XCTAssertEqual(events.last, .completed)
        XCTAssertEqual(progress.segments.map(\.endElapsed), [100, 200, 300])
        // Die Strecke dazwischen kennt die Engine nicht: Sie gehört zur letzten Meldung davor.
        XCTAssertEqual(progress.segments.map(\.meters), [0, 0, 0])
    }

    // MARK: - Wiederholungen nach Strecke

    func testDistanceRepetitionsCarryOverWithoutRest() {
        var progress = SessionProgress(steps: [Self.distance("Bahnen", 50, repetitions: 4)])
        progress.update(meters: 25, elapsed: 30)
        // Eine Meldung fehlt: von 25 auf 75 m.
        let events = progress.update(meters: 75, elapsed: 90)

        XCTAssertEqual(events.count, 2)
        guard case let .work(unit, done, remaining) = progress.status(meters: 75, elapsed: 90) else { return XCTFail("Satz erwartet") }
        XCTAssertEqual(unit.repetition, 2)
        XCTAssertEqual(done, 25)
        XCTAssertEqual(remaining, 25)
        XCTAssertEqual(progress.segments.first?.meters, 50)
    }

    func testDistanceDuringRestDoesNotCountButTheNextLengthDoes() {
        var progress = SessionProgress(steps: [Self.distance("Hauptsatz", 100, repetitions: 2, rest: 20)])
        progress.update(meters: 100, elapsed: 60)
        XCTAssertEqual(progress.phase, .rest(endsAt: 80))

        // In der Pause noch eine Bahn ausgeschwommen: zählt nicht.
        progress.update(meters: 125, elapsed: 75)
        // Die erste Meldung nach der Pause bringt die erste Bahn der nächsten Wiederholung.
        let events = progress.update(meters: 150, elapsed: 90)

        XCTAssertEqual(events.count, 1)
        guard case let .work(unit, done, _) = progress.status(meters: 150, elapsed: 90) else { return XCTFail("Satz erwartet") }
        XCTAssertEqual(unit.repetition, 2)
        XCTAssertEqual(done, 25)
    }

    // MARK: - Von Hand

    func testBackViaCrownRestartsThePreviousInterval() {
        var progress = SessionProgress(steps: Self.intervals)
        run(&progress, from: 0, through: 1200)
        // Mitten im dritten Intervall (Start 1140).
        XCTAssertEqual(progress.current?.repetition, 3)

        let events = progress.move(.previous, meters: 3600, elapsed: 1200)

        XCTAssertEqual(events.count, 1)
        guard case let .workStarted(unit) = events.first else { return XCTFail("Neustart erwartet") }
        XCTAssertEqual(unit.repetition, 2)
        // Das verworfene zweite Intervall steht nicht mehr in den Abschnitten.
        XCTAssertEqual(progress.segments.filter { $0.unit.step.name == "Intervall" }.count, 1)

        // Das wiederholte Intervall dauert wieder 3:00 ab jetzt.
        let later = run(&progress, from: 1201, through: 1400)
        XCTAssertEqual(later.filter { isRest($0.event) }.map(\.second), [1380])
    }

    func testBackDuringRestRepeatsTheIntervalJustDone() {
        var progress = SessionProgress(steps: Self.intervals)
        run(&progress, from: 0, through: 800)
        XCTAssertEqual(progress.phase, .rest(endsAt: 870))
        XCTAssertTrue(progress.canMove(.previous))

        progress.move(.previous, meters: 2400, elapsed: 800)

        XCTAssertEqual(progress.phase, .work)
        XCTAssertEqual(progress.current?.repetition, 1)
        XCTAssertEqual(progress.segments.count, 1)
    }

    func testBackIsImpossibleInTheFirstUnitAndAfterTheEndRestartsTheLast() {
        var progress = SessionProgress(steps: [Self.timed("A", 60), Self.timed("B", 60)])
        progress.update(meters: 0, elapsed: 10)
        XCTAssertFalse(progress.canMove(.previous))
        XCTAssertEqual(progress.move(.previous, meters: 0, elapsed: 20), [])
        XCTAssertEqual(progress.current?.step.name, "A")

        progress.update(meters: 0, elapsed: 200)
        XCTAssertTrue(progress.isCompleted)
        XCTAssertFalse(progress.canMove(.next))
        XCTAssertEqual(progress.move(.next, meters: 0, elapsed: 201), [])

        let events = progress.move(.previous, meters: 0, elapsed: 210)
        guard case let .workStarted(unit) = events.first else { return XCTFail("Neustart erwartet") }
        XCTAssertEqual(unit.step.name, "B")
        XCTAssertEqual(progress.segments.map(\.unit.step.name), ["A"])
        progress.update(meters: 0, elapsed: 270)
        XCTAssertTrue(progress.isCompleted)
    }

    func testNextEndsTheRepetitionEarlyThenSkipsTheRest() {
        var progress = SessionProgress(steps: [Self.distance("Hauptsatz", 200, repetitions: 2, rest: 30)])
        progress.update(meters: 150, elapsed: 100)

        let ended = progress.move(.next, meters: 150, elapsed: 100)
        guard case let .workEnded(segment) = ended.first else { return XCTFail("Ende erwartet") }
        XCTAssertFalse(segment.reachedTarget)
        XCTAssertEqual(segment.meters, 150)
        XCTAssertEqual(progress.phase, .rest(endsAt: 130))

        let skipped = progress.move(.next, meters: 150, elapsed: 105)
        guard case let .workStarted(unit) = skipped.first else { return XCTFail("Start erwartet") }
        XCTAssertEqual(unit.repetition, 2)
        progress.update(meters: 350, elapsed: 200)
        XCTAssertTrue(progress.isCompleted)
    }

    func testRepetitionWithoutDistanceOrTimeEndsOnlyByHand() {
        let strength = PlanStep(name: "Kniebeugen", repetitions: 2, measure: .repetitions)
        var progress = SessionProgress(steps: [strength])
        XCTAssertNil(progress.units.first?.target)

        XCTAssertEqual(progress.update(meters: 500, elapsed: 600), [])
        guard case let .work(_, done, remaining) = progress.status(meters: 500, elapsed: 600) else { return XCTFail("Arbeit erwartet") }
        XCTAssertEqual(done, 600)
        XCTAssertNil(remaining)

        let events = progress.move(.next, meters: 500, elapsed: 600)
        guard case let .workEnded(segment) = events.first else { return XCTFail("Ende erwartet") }
        XCTAssertTrue(segment.reachedTarget)
        XCTAssertEqual(progress.current?.repetition, 2)
    }

    // MARK: - Aufbau und Ende

    func testUnitsSkipEmptyStepsAndUseWhatAStepHas() {
        let steps = [
            PlanStep(name: "ohne Wiederholung", repetitions: 0, measure: .distance, distanceMeters: 100),
            PlanStep(name: "Strecke ohne Meter", repetitions: 1, measure: .distance, durationSeconds: 60),
            PlanStep(name: "Zeit ohne Sekunden", repetitions: 1, measure: .duration, distanceMeters: 100),
            PlanStep(name: "unbekanntes Maß mit Zeit", repetitions: 1, measure: nil, durationSeconds: 90, restSeconds: 15),
            PlanStep(name: "unbekanntes Maß mit Strecke", repetitions: 1, measure: nil, distanceMeters: 400, restSeconds: 15)
        ]

        let units = ProgressUnit.units(for: steps)

        XCTAssertEqual(units.map(\.step.name), ["unbekanntes Maß mit Zeit", "unbekanntes Maß mit Strecke"])
        XCTAssertEqual(units.map(\.target), [.seconds(90), .meters(400)])
        XCTAssertEqual(units.map(\.stepIndex), [3, 4])
        XCTAssertEqual(units.map(\.index), [0, 1])
        // Nach der letzten Wiederholung keine Pause mehr.
        XCTAssertEqual(units.map(\.restSeconds), [15, 0])
    }

    func testWithoutStepsThereIsNothingToFollow() {
        var progress = SessionProgress(steps: [])
        XCTAssertEqual(progress.status(meters: 100, elapsed: 100), .noUnits)
        XCTAssertEqual(progress.update(meters: 100, elapsed: 100), [])
        XCTAssertFalse(progress.canMove(.next))
        XCTAssertFalse(progress.canMove(.previous))
        XCTAssertFalse(progress.isCompleted)
        XCTAssertEqual(progress.status(meters: 0, elapsed: 0), .noUnits)
    }

    func testCompletedStatus() {
        var progress = SessionProgress(steps: [Self.timed("A", 60)])
        progress.update(meters: 0, elapsed: 60)
        XCTAssertEqual(progress.status(meters: 0, elapsed: 61), .completed)
    }

    func testFinishRecordsTheRunningRepetitionAsNotReached() {
        var progress = SessionProgress(steps: [Self.timed("Test 30 Minuten", 1800)])
        progress.update(meters: 0, elapsed: 0)

        progress.finish(meters: 3000, elapsed: 1080)
        progress.finish(meters: 3200, elapsed: 1100)

        XCTAssertEqual(progress.segments.count, 1)
        XCTAssertEqual(progress.segments.first?.reachedTarget, false)
        XCTAssertEqual(progress.segments.first?.duration, 1080)
        XCTAssertEqual(progress.segments.first?.meters, 3000)
        // Danach ändert sich nichts mehr.
        XCTAssertEqual(progress.update(meters: 9000, elapsed: 4000), [])
        XCTAssertFalse(progress.canMove(.next))
    }

    func testFinishDuringRestAddsNothing() {
        var progress = SessionProgress(steps: [Self.timed("A", 60, repetitions: 2, rest: 60)])
        progress.update(meters: 0, elapsed: 70)
        progress.finish(meters: 0, elapsed: 80)
        XCTAssertEqual(progress.segments.count, 1)
    }

    func testSmallerOrBrokenReadingsCountAsTheLastOne() {
        var progress = SessionProgress(steps: [Self.distance("Bahnen", 100, repetitions: 2)])
        progress.update(meters: 80, elapsed: 60)
        XCTAssertEqual(progress.update(meters: 20, elapsed: 30), [])
        XCTAssertEqual(progress.update(meters: .nan, elapsed: .infinity), [])
        guard case let .work(_, done, _) = progress.status(meters: 0, elapsed: 0) else { return XCTFail("Satz erwartet") }
        XCTAssertEqual(done, 80)
    }
}
