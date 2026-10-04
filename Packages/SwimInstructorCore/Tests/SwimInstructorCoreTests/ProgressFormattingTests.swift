import XCTest
@testable import SwimInstructorCore

/// Texte der Watch zum Stand in der Einheit: Anzeige und Ansagen.
final class ProgressFormattingTests: XCTestCase {
    private static let intervals = PlanStep(
        name: "Intervalle", repetitions: 6, measure: .duration, durationSeconds: 180,
        targetType: .heartRateZone, targetValue: 4, restSeconds: 90
    )
    private static let swimSet = PlanStep(name: "Hauptsatz", repetitions: 1, measure: .distance, distanceMeters: 1500, cue: "Lang ziehen")
    private static let strength = PlanStep(name: "Rumpf", repetitions: 1, measure: .repetitions)

    private func unit(_ step: PlanStep, stepIndex: Int = 1, repetition: Int = 1) -> ProgressUnit {
        ProgressUnit.units(for: Array(repeating: step, count: stepIndex + 1))
            .first { $0.stepIndex == stepIndex && $0.repetition == repetition }!
    }

    // MARK: - Anzeige

    func testStepTitleNumbersTheSteps() {
        XCTAssertEqual(ProgressFormatting.stepTitle(unit(Self.intervals), stepCount: 5), "2/5 Intervalle")
        // Nie weniger Schritte als die Nummer.
        XCTAssertEqual(ProgressFormatting.stepTitle(unit(Self.intervals), stepCount: 0), "2/2 Intervalle")
    }

    func testRepetitionOnlyForRepeatedSteps() {
        XCTAssertEqual(ProgressFormatting.repetition(unit(Self.intervals, repetition: 3)), "3 von 6")
        XCTAssertNil(ProgressFormatting.repetition(unit(Self.swimSet)))
    }

    func testTargetOfARepetition() {
        XCTAssertEqual(ProgressFormatting.target(unit(Self.intervals)), "3:00 min")
        XCTAssertEqual(ProgressFormatting.target(unit(Self.swimSet)), "1.500 m")
        XCTAssertEqual(ProgressFormatting.target(unit(Self.strength)), "von Hand")
    }

    func testRemainingForEveryState() {
        let interval = unit(Self.intervals, repetition: 3)
        let swim = unit(Self.swimSet)
        let manual = unit(Self.strength)

        XCTAssertEqual(ProgressFormatting.remaining(.noUnits), "Freies Training")
        XCTAssertEqual(ProgressFormatting.remaining(.completed), "Plan geschafft")
        XCTAssertEqual(ProgressFormatting.remaining(.rest(after: interval, next: nil, remainingSeconds: 25)), "Pause 0:25")
        XCTAssertEqual(ProgressFormatting.remaining(.work(swim, done: 1350.4, remaining: 149.6)), "noch 150 m")
        XCTAssertEqual(ProgressFormatting.remaining(.work(interval, done: 96.7, remaining: 83.3)), "noch 1:24")
        XCTAssertEqual(ProgressFormatting.remaining(.work(manual, done: 75, remaining: nil)), "1:15")
    }

    func testLineAddsTheRepetition() {
        let interval = unit(Self.intervals, repetition: 3)

        XCTAssertEqual(ProgressFormatting.line(.work(interval, done: 97, remaining: 83)), "3 von 6 · noch 1:23")
        XCTAssertEqual(ProgressFormatting.line(.work(unit(Self.swimSet), done: 1000, remaining: 500)), "noch 500 m")
        XCTAssertEqual(ProgressFormatting.line(.rest(after: interval, next: nil, remainingSeconds: 90)), "Pause 1:30")
        XCTAssertEqual(ProgressFormatting.line(.completed), "Plan geschafft")
    }

    func testCueFromThePlanOrFromTargetAndGoal() {
        XCTAssertEqual(ProgressFormatting.cue(unit(Self.swimSet)), "Lang ziehen")
        XCTAssertEqual(ProgressFormatting.cue(unit(Self.intervals)), "3:00 min · Zone 4")
        XCTAssertEqual(ProgressFormatting.cue(unit(Self.strength)), "von Hand")
    }

    // MARK: - Ansagen

    func testAnnouncementsWhenWorkAndRestStart() {
        XCTAssertEqual(
            ProgressFormatting.announcement(.workStarted(unit(Self.intervals, repetition: 2))),
            "Intervalle, 2 von 6. 3:00 min · Zone 4."
        )
        XCTAssertEqual(ProgressFormatting.announcement(.workStarted(unit(Self.swimSet))), "Hauptsatz. Lang ziehen.")
        XCTAssertEqual(ProgressFormatting.announcement(.restStarted(unit(Self.intervals))), "Pause, 1 Minute 30.")
        XCTAssertEqual(ProgressFormatting.announcement(.completed), "Plan geschafft.")
    }

    func testTheEndOfARepetitionIsOnlyAnnouncedInATest() {
        let test = PlanStep(name: "Test 400 m", repetitions: 1, measure: .distance, distanceMeters: 400, targetType: .perceivedEffort, targetValue: 10)
        let testUnit = unit(test)

        let reached = RecordedSegment(unit: testUnit, startElapsed: 100, endElapsed: 472, meters: 400, reachedTarget: true)
        let aborted = RecordedSegment(unit: testUnit, startElapsed: 100, endElapsed: 300, meters: 250, reachedTarget: false)
        let training = RecordedSegment(unit: unit(Self.swimSet), startElapsed: 0, endElapsed: 1500, meters: 1500, reachedTarget: true)

        XCTAssertEqual(ProgressFormatting.announcement(.workEnded(reached)), "Geschafft. Zeit 6 Minuten 12.")
        XCTAssertNil(ProgressFormatting.announcement(.workEnded(aborted)))
        XCTAssertNil(ProgressFormatting.announcement(.workEnded(training)))
    }

    func testSpokenDuration() {
        XCTAssertEqual(ProgressFormatting.spokenDuration(45), "45 Sekunden")
        XCTAssertEqual(ProgressFormatting.spokenDuration(59.6), "1 Minute")
        XCTAssertEqual(ProgressFormatting.spokenDuration(120), "2 Minuten")
        XCTAssertEqual(ProgressFormatting.spokenDuration(372), "6 Minuten 12")
        XCTAssertEqual(ProgressFormatting.spokenDuration(-3), "0 Sekunden")
    }
}
