import XCTest
@testable import SwimInstructorCore

final class TrainingLoadTests: XCTestCase {
    private func workout(_ sport: SportID, minutes: Double, heartRate: Double? = nil, effort: Double? = nil) -> Workout {
        Workout(
            id: UUID(), sport: sport, startDate: Date(), endDate: Date().addingTimeInterval(minutes * 60),
            duration: minutes * 60, averageHeartRate: heartRate, metrics: effort.map { [.effort: $0] } ?? [:]
        )
    }

    func testWithoutHeartRateLoadIsMinutesTimesSportFactor() {
        let calculator = TrainingLoadCalculator()
        XCTAssertEqual(calculator.load(of: workout(.run, minutes: 60)), 60, accuracy: 0.001)
        XCTAssertEqual(calculator.load(of: workout(.bike, minutes: 60)), 48, accuracy: 0.001)
        // Unbekannte Sportart zählt wie Laufen, statt zu verschwinden.
        XCTAssertEqual(calculator.load(of: workout("kayak", minutes: 30)), 30, accuracy: 0.001)
        XCTAssertEqual(calculator.load(of: workout(.run, minutes: -5)), 0)
    }

    func testHeartRateNeedsRestingAndMaximum() {
        let onlyResting = TrainingLoadCalculator(restingHeartRate: 50)
        XCTAssertEqual(onlyResting.load(of: workout(.run, minutes: 60, heartRate: 150)), 60, accuracy: 0.001)
        let swapped = TrainingLoadCalculator(restingHeartRate: 190, maximumHeartRate: 50)
        XCTAssertEqual(swapped.load(of: workout(.run, minutes: 60, heartRate: 150)), 60, accuracy: 0.001)
    }

    func testSessionRpeFromHeartRateReserve() {
        let calculator = TrainingLoadCalculator(restingHeartRate: 50, maximumHeartRate: 190)
        // Reserve (120 - 50) / 140 = 0,5 → Anstrengung 12 × 0,5 - 3 = 3 → 60 × 3 / 4.
        XCTAssertEqual(calculator.load(of: workout(.run, minutes: 60, heartRate: 120)), 45, accuracy: 0.001)
        XCTAssertEqual(calculator.load(of: workout(.bike, minutes: 60, heartRate: 120)), 36, accuracy: 0.001)
        // Puls unter Ruhe: Anstrengung 1; über Maximum: Reserve 1 → 9.
        XCTAssertEqual(calculator.load(of: workout(.run, minutes: 60, heartRate: 40)), 15, accuracy: 0.001)
        XCTAssertEqual(calculator.load(of: workout(.run, minutes: 60, heartRate: 220)), 135, accuracy: 0.001)
        XCTAssertGreaterThan(
            calculator.load(of: workout(.run, minutes: 60, heartRate: 170)),
            calculator.load(of: workout(.run, minutes: 60, heartRate: 130))
        )
    }

    func testRatedEffortFromHealthGoesBeforeHeartRate() {
        let calculator = TrainingLoadCalculator(restingHeartRate: 50, maximumHeartRate: 190)
        // Session-RPE: 60 min × Anstrengung 8 / 4.
        XCTAssertEqual(calculator.load(of: workout(.run, minutes: 60, heartRate: 120, effort: 8)), 120, accuracy: 0.001)
        XCTAssertEqual(TrainingLoadCalculator().load(of: workout(.bike, minutes: 60, effort: 2)), 24, accuracy: 0.001)
        // Werte außerhalb 0 bis 10 werden begrenzt.
        XCTAssertEqual(calculator.effort(of: workout(.run, minutes: 60, effort: 14)), 10)
        XCTAssertEqual(calculator.effort(of: workout(.run, minutes: 60, effort: -1)), 0)
        XCTAssertEqual(calculator.effort(of: workout(.run, minutes: 60, effort: .nan)), TrainingLoadCalculator.referenceEffort)
    }

    func testLoadBySportSumsPerSport() {
        let calculator = TrainingLoadCalculator()
        let loads = calculator.loadBySport([
            workout(.swim, minutes: 45), workout(.run, minutes: 30), workout(.run, minutes: 20), workout(.bike, minutes: 100)
        ])
        XCTAssertEqual(loads[.swim] ?? -1, 45, accuracy: 0.001)
        XCTAssertEqual(loads[.run] ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(loads[.bike] ?? -1, 80, accuracy: 0.001)
        XCTAssertTrue(calculator.loadBySport([]).isEmpty)
    }
}
