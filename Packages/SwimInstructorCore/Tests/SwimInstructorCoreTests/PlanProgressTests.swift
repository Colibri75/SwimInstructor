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

    func testAnAdvanceDuringALaterSetBelongsToThatSet() {
        // Einschwimmen regulär beendet (300 m), im Hauptsatz bei 700 m "weiter": ab da Ausschwimmen.
        let position = position(state(750, advancedAt: [700]))

        XCTAssertEqual(position?.set.name, "Ausschwimmen")
        XCTAssertEqual(position?.metersIntoRepetition, 50)
    }

    func testTwoAdvancesSkipTwoSets() {
        let position = position(state(100, advancedAt: [100, 100]))

        XCTAssertEqual(position?.set.name, "Ausschwimmen")
        XCTAssertEqual(position?.metersIntoRepetition, 0)
    }

    func testAdvancingInTheLastSetCompletesThePlan() {
        // 300 + 1200 = 1500 m, Ausschwimmen läuft; bei 1550 m "weiter" beendet den Plan.
        XCTAssertEqual(state(1550, advancedAt: [1550]), .completed(extraMeters: 0))
        XCTAssertEqual(state(1580, advancedAt: [1550]), .completed(extraMeters: 30))
    }

    func testAdvancesAreSortedAndNegativeValuesCountAsZero() {
        let position = position(state(250, advancedAt: [200, -5]))

        // -5 zählt als 0: Der erste Druck beendet das Einschwimmen sofort, der zweite bei 200 m den Hauptsatz.
        XCTAssertEqual(position?.set.name, "Ausschwimmen")
    }

    func testAdvanceDoesNotAffectPlansWithoutSets() {
        XCTAssertEqual(PlanProgress.state(sets: [], swumMeters: 100, advancedAt: [50]), .noSets)
    }
}
