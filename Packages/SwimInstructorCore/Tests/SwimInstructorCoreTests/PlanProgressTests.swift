import XCTest
@testable import SwimInstructorCore

final class PlanProgressTests: XCTestCase {
    private let sets = [
        PlanSet(name: "Einschwimmen", repetitions: 1, distanceMeters: 300, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: ""),
        PlanSet(name: "Hauptsatz", repetitions: 6, distanceMeters: 200, targetPaceSecondsPerHundredMeters: 140, restSeconds: 30, instructions: ""),
        PlanSet(name: "Ausschwimmen", repetitions: 1, distanceMeters: 100, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: "")
    ]

    private func position(_ meters: Double) -> PlanPosition? {
        if case let .inProgress(position) = PlanProgress.state(sets: sets, swumMeters: meters) {
            return position
        }
        return nil
    }

    func testStartIsFirstSet() {
        let position = position(0)

        XCTAssertEqual(position?.setIndex, 0)
        XCTAssertEqual(position?.repetition, 1)
        XCTAssertEqual(position?.metersRemainingInRepetition, 300)
    }

    func testMidwayThroughRepetition() {
        // 300 m Einschwimmen + 2 × 200 m + 50 m = 750 m → dritte Wiederholung, 50 m drin.
        let position = position(750)

        XCTAssertEqual(position?.set.name, "Hauptsatz")
        XCTAssertEqual(position?.repetition, 3)
        XCTAssertEqual(position?.metersIntoRepetition, 50)
        XCTAssertEqual(position?.metersRemainingInRepetition, 150)
    }

    func testExactSetBoundaryStartsNextSet() {
        let position = position(300)

        XCTAssertEqual(position?.set.name, "Hauptsatz")
        XCTAssertEqual(position?.repetition, 1)
        XCTAssertEqual(position?.metersIntoRepetition, 0)
    }

    func testFractionalMetersRoundDown() {
        XCTAssertEqual(position(299.9)?.set.name, "Einschwimmen")
    }

    func testLastSet() {
        let position = position(1550)

        XCTAssertEqual(position?.set.name, "Ausschwimmen")
        XCTAssertEqual(position?.metersRemainingInRepetition, 50)
    }

    func testCompletedWithExtraMeters() {
        XCTAssertEqual(PlanProgress.state(sets: sets, swumMeters: 1600), .completed(extraMeters: 0))
        XCTAssertEqual(PlanProgress.state(sets: sets, swumMeters: 1675), .completed(extraMeters: 75))
    }

    func testSetsWithoutDistanceAreSkipped() {
        let withEmpty = [
            PlanSet(name: "Dehnen", repetitions: 1, distanceMeters: 0, targetPaceSecondsPerHundredMeters: nil, restSeconds: 0, instructions: ""),
            sets[0]
        ]

        guard case let .inProgress(position) = PlanProgress.state(sets: withEmpty, swumMeters: 100) else {
            return XCTFail("erwartet: läuft")
        }
        XCTAssertEqual(position.setIndex, 1)
        XCTAssertEqual(position.set.name, "Einschwimmen")
    }

    func testNoSets() {
        XCTAssertEqual(PlanProgress.state(sets: [], swumMeters: 500), .noSets)
    }

    func testNegativeDistanceCountsAsZero() {
        XCTAssertEqual(position(-10)?.metersIntoRepetition, 0)
    }

    // MARK: - Abschnitt von Hand weiterschalten

    private func state(_ meters: Double, advancedAt: [Double]) -> PlanProgressState {
        PlanProgress.state(sets: sets, swumMeters: meters, advancedAt: advancedAt)
    }

    private func position(_ state: PlanProgressState) -> PlanPosition? {
        if case let .inProgress(position) = state { return position }
        return nil
    }

    func testAdvancingEndsTheCurrentSetAndStartsTheNextOneRightThere() {
        // Einschwimmen nach 200 m abgebrochen: Der Hauptsatz beginnt bei 200 m.
        let atPress = position(state(200, advancedAt: [200]))
        XCTAssertEqual(atPress?.set.name, "Hauptsatz")
        XCTAssertEqual(atPress?.repetition, 1)
        XCTAssertEqual(atPress?.metersRemainingInRepetition, 200)

        // 250 m: 50 m in der ersten Wiederholung des Hauptsatzes (ohne Druck wäre es noch Einschwimmen).
        let later = position(state(250, advancedAt: [200]))
        XCTAssertEqual(later?.set.name, "Hauptsatz")
        XCTAssertEqual(later?.repetition, 1)
        XCTAssertEqual(later?.metersIntoRepetition, 50)
    }

    func testWithoutAdvancesNothingChanges() {
        XCTAssertEqual(state(750, advancedAt: []), PlanProgress.state(sets: sets, swumMeters: 750))
    }

    func testAnAdvanceDuringALaterSetSkipsOnlyTheRunningRepetition() {
        // Einschwimmen regulär beendet (300 m), Sätze 1 und 2 regulär (bis 700 m): "weiter" im dritten
        // Satz (bei 700 m) beginnt den vierten dort. Der Hauptsatz bleibt der Abschnitt.
        let position = position(state(750, advancedAt: [700]))

        XCTAssertEqual(position?.set.name, "Hauptsatz")
        XCTAssertEqual(position?.repetition, 4)
        XCTAssertEqual(position?.metersIntoRepetition, 50)
    }

    func testAdvancingInTheMiddleOfARepetitionStartsTheNextRepetitionThere() {
        // 150 m im ersten Satz des Hauptsatzes (bei 450 m insgesamt): "weiter" beginnt Satz 2 dort.
        let position = position(state(500, advancedAt: [450]))

        XCTAssertEqual(position?.set.name, "Hauptsatz")
        XCTAssertEqual(position?.repetition, 2)
        XCTAssertEqual(position?.metersIntoRepetition, 50)
    }

    func testTheLastRepetitionOfASectionLeadsToTheNextSection() {
        // Hauptsatz bis 1500 m; "weiter" im sechsten Satz bei 1400 m: Ausschwimmen beginnt dort.
        let position = position(state(1450, advancedAt: [1400]))

        XCTAssertEqual(position?.set.name, "Ausschwimmen")
        XCTAssertEqual(position?.metersIntoRepetition, 50)
    }

    func testTwoAdvancesSkipTwoRepetitions() {
        let position = position(state(100, advancedAt: [100, 100]))

        XCTAssertEqual(position?.set.name, "Hauptsatz")
        XCTAssertEqual(position?.repetition, 2)
        XCTAssertEqual(position?.metersIntoRepetition, 0)
    }

    func testAdvancingInTheLastSetCompletesThePlan() {
        // 300 + 1200 = 1500 m, Ausschwimmen läuft; bei 1550 m "weiter" beendet den Plan.
        XCTAssertEqual(state(1550, advancedAt: [1550]), .completed(extraMeters: 0))
        XCTAssertEqual(state(1580, advancedAt: [1550]), .completed(extraMeters: 30))
    }

    func testAdvancesAreSortedAndNegativeValuesCountAsZero() {
        let position = position(state(250, advancedAt: [200, -5]))

        // -5 zählt als 0: Der erste Druck beendet das Einschwimmen sofort, der zweite bei 200 m den
        // ersten Satz des Hauptsatzes. Der dritte Satz beginnt bei 200 m.
        XCTAssertEqual(position?.set.name, "Hauptsatz")
        XCTAssertEqual(position?.repetition, 3)
        XCTAssertEqual(position?.metersIntoRepetition, 50)
    }

    func testAdvanceDoesNotAffectPlansWithoutSets() {
        XCTAssertEqual(PlanProgress.state(sets: [], swumMeters: 100, advancedAt: [50]), .noSets)
    }

    // MARK: - Nummer des Abschnitts

    func testSectionIndexFollowsTheSetAndEndsAtTheSetCount() {
        XCTAssertEqual(PlanProgress.state(sets: sets, swumMeters: 0).sectionIndex(setCount: sets.count), 0)
        XCTAssertEqual(PlanProgress.state(sets: sets, swumMeters: 300).sectionIndex(setCount: sets.count), 1)
        XCTAssertEqual(PlanProgress.state(sets: sets, swumMeters: 1500).sectionIndex(setCount: sets.count), 2)
        XCTAssertEqual(PlanProgress.state(sets: sets, swumMeters: 1600).sectionIndex(setCount: sets.count), 3)
        XCTAssertEqual(PlanProgress.state(sets: [], swumMeters: 50).sectionIndex(setCount: 0), 0)
    }

    func testAdvancingAtZeroMetersStillMovesToTheNextSet() {
        // Kommt die Strecke aus Health nicht an (0 m), muss die Taste trotzdem weiterschalten.
        let state = PlanProgress.state(sets: sets, swumMeters: 0, advancedAt: [0])

        XCTAssertEqual(state.sectionIndex(setCount: sets.count), 1)
    }

    // MARK: - Abschnitt zurück

    private func state(_ meters: Double, moves: [SectionMove]) -> PlanProgressState {
        PlanProgress.state(sets: sets, swumMeters: meters, moves: moves)
    }

    private func move(_ meters: Double, _ direction: SectionDirection) -> SectionMove {
        SectionMove(meters: meters, direction: direction)
    }

    func testGoingBackRestartsThePreviousRepetitionAtThatPoint() {
        // Zweiter Satz des Hauptsatzes läuft bei 500 m, zurück: Satz 1 beginnt dort von vorn.
        let atPress = position(state(500, moves: [move(500, .previous)]))
        XCTAssertEqual(atPress?.set.name, "Hauptsatz")
        XCTAssertEqual(atPress?.repetition, 1)
        XCTAssertEqual(atPress?.metersIntoRepetition, 0)

        let later = position(state(560, moves: [move(500, .previous)]))
        XCTAssertEqual(later?.repetition, 1)
        XCTAssertEqual(later?.metersIntoRepetition, 60)
    }

    func testGoingBackFromTheFirstRepetitionLeadsToThePreviousSection() {
        // Erster Satz des Hauptsatzes läuft bei 320 m, zurück: Einschwimmen beginnt dort von vorn.
        let position = position(state(350, moves: [move(320, .previous)]))

        XCTAssertEqual(position?.set.name, "Einschwimmen")
        XCTAssertEqual(position?.metersIntoRepetition, 30)
    }

    func testForwardAndBackCancelOut() {
        // Bei 100 m weiter (Hauptsatz ab 100), bei 150 m zurück (Einschwimmen ab 150).
        let position = position(state(200, moves: [move(100, .next), move(150, .previous)]))

        XCTAssertEqual(position?.set.name, "Einschwimmen")
        XCTAssertEqual(position?.metersIntoRepetition, 50)
    }

    func testGoingBackInTheFirstSetRestartsIt() {
        let position = position(state(120, moves: [move(100, .previous)]))

        XCTAssertEqual(position?.set.name, "Einschwimmen")
        XCTAssertEqual(position?.metersIntoRepetition, 20)
    }

    func testGoingBackAfterTheEndReopensTheLastSet() {
        // Plan nach 1600 m geschafft; bei 1620 m zurück: Ausschwimmen beginnt dort wieder.
        let position = position(state(1650, moves: [move(1620, .previous)]))

        XCTAssertEqual(position?.set.name, "Ausschwimmen")
        XCTAssertEqual(position?.metersIntoRepetition, 30)
    }

    func testMovesAreAppliedInTheOrderTheyHappened() {
        // Zwei Mal weiter bei 100 m, einmal zurück bei 100 m: Hauptsatz.
        let position = position(state(100, moves: [move(100, .next), move(100, .next), move(100, .previous)]))

        XCTAssertEqual(position?.set.name, "Hauptsatz")
        XCTAssertEqual(position?.metersIntoRepetition, 0)
    }

    func testForwardAfterTheEndDoesNothing() {
        XCTAssertEqual(state(1700, moves: [move(1650, .next)]), .completed(extraMeters: 100))
    }

    func testGoingBackWorksWithoutDistanceFromHealth() {
        // 0 m: weiter, dann zurück ergibt wieder den ersten Abschnitt.
        let state = PlanProgress.state(sets: sets, swumMeters: 0, moves: [move(0, .next), move(0, .previous)])

        XCTAssertEqual(state.sectionIndex(setCount: sets.count), 0)
    }

    func testStepKeyChangesWithEveryRepetitionAndSection() {
        let keys = [0.0, 300, 500, 1500, 1600].map { PlanProgress.state(sets: sets, swumMeters: $0).stepKey }

        XCTAssertEqual(keys, keys.sorted())
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(keys.last, Int.max)
        XCTAssertEqual(PlanProgress.state(sets: [], swumMeters: 10).stepKey, 0)
    }
}
