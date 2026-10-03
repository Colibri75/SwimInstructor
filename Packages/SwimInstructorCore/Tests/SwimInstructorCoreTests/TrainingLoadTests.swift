import XCTest
@testable import SwimInstructorCore

final class TrainingLoadTests: XCTestCase {
    private func workout(_ sport: SportID, minutes: Double, heartRate: Double? = nil) -> Workout {
        Workout(
            id: UUID(), sport: sport, startDate: Date(), endDate: Date().addingTimeInterval(minutes * 60),
            duration: minutes * 60, averageHeartRate: heartRate
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

    func testBanisterTrimpWithHeartRateReserve() {
        let calculator = TrainingLoadCalculator(restingHeartRate: 50, maximumHeartRate: 190)
        // Reserve (120 - 50) / 140 = 0,5 → 60 × 0,5 × 0,64 × e^0,96
        let expected = 60 * 0.5 * 0.64 * exp(1.92 * 0.5)
        XCTAssertEqual(calculator.load(of: workout(.run, minutes: 60, heartRate: 120)), expected, accuracy: 0.001)
        XCTAssertEqual(calculator.load(of: workout(.bike, minutes: 60, heartRate: 120)), expected * 0.8, accuracy: 0.001)
        // Puls unter Ruhe oder über Maximum wird begrenzt.
        XCTAssertEqual(calculator.load(of: workout(.run, minutes: 60, heartRate: 40)), 0)
        XCTAssertEqual(
            calculator.load(of: workout(.run, minutes: 60, heartRate: 220)),
            60 * 0.64 * exp(1.92),
            accuracy: 0.001
        )
        XCTAssertGreaterThan(
            calculator.load(of: workout(.run, minutes: 60, heartRate: 170)),
            calculator.load(of: workout(.run, minutes: 60, heartRate: 130))
        )
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
