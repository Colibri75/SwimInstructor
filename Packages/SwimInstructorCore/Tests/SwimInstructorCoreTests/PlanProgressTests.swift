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
}
