import XCTest
@testable import SwimInstructorCore

/// Was die Watch während einer Einheit mitschreibt, und die Rechnungen über die Messreihen.
final class WorkoutRecordingTests: XCTestCase {
    private func series(_ pairs: [(TimeInterval, Double)]) -> [TimedValue] {
        pairs.map { TimedValue(elapsed: $0.0, value: $0.1) }
    }

    // MARK: - Mitschreiben

    func testHeartRateAndPowerStaySortedByTime() {
        var recording = WorkoutRecording()

        recording.recordHeartRate(120, at: 5)
        recording.recordHeartRate(125, at: 10)
        recording.recordHeartRate(130, at: 10)
        recording.recordHeartRate(110, at: 7)
        recording.recordPower(200, at: 3)
        recording.recordPower(210, at: 4)

        // Dieselbe Zeit ersetzt den Wert, eine ältere Messung zählt nicht.
        XCTAssertEqual(recording.heartRate, series([(5, 120), (10, 130)]))
        XCTAssertEqual(recording.power, series([(3, 200), (4, 210)]))
    }

    func testInvalidSamplesAreIgnored() {
        var recording = WorkoutRecording()

        recording.recordHeartRate(.nan, at: 1)
        recording.recordHeartRate(120, at: .infinity)
        recording.recordHeartRate(120, at: -1)
        recording.recordPower(.infinity, at: 2)

        XCTAssertEqual(recording.heartRate, [])
        XCTAssertEqual(recording.power, [])
    }

    func testDistanceOnlyGrows() {
        var recording = WorkoutRecording()

        recording.recordDistance(0, at: 0)
        recording.recordDistance(10, at: 5)
        recording.recordDistance(10, at: 6)
        recording.recordDistance(8, at: 7)
        recording.recordDistance(25, at: 10)

        XCTAssertEqual(recording.distance, series([(0, 0), (5, 10), (10, 25)]))
    }

    func testLapsAreCountedOnce() {
        var recording = WorkoutRecording(lapLengthMeters: 25)

        recording.recordLap(start: 0, end: 30)
        recording.recordLap(start: 0, end: 30)
        recording.recordLap(start: 30, end: 58)
        recording.recordLap(start: 10, end: 20)
        recording.recordLap(start: 70, end: 60)
        recording.recordLap(start: .nan, end: 90)
        recording.recordLap(start: 60, end: .infinity)

        XCTAssertEqual(recording.laps, [LapTime(start: 0, end: 30), LapTime(start: 30, end: 58)])
        XCTAssertEqual(recording.lapLengthMeters, 25)
    }

    func testSeriesStopAtTheirLimit() {
        var recording = WorkoutRecording()

        for second in 0...WorkoutRecording.sampleLimit {
            recording.recordHeartRate(120, at: TimeInterval(second))
        }
        // Am Limit ersetzt eine Messung zur selben Zeit noch den letzten Wert.
        recording.recordHeartRate(150, at: TimeInterval(WorkoutRecording.sampleLimit - 1))

        XCTAssertEqual(recording.heartRate.count, WorkoutRecording.sampleLimit)
        XCTAssertEqual(recording.heartRate.last, TimedValue(elapsed: TimeInterval(WorkoutRecording.sampleLimit - 1), value: 150))
    }

    // MARK: - Rechnungen über die Reihen

    func testValuesAndMeanInAWindow() {
        let values = series([(0, 100), (10, 120), (20, 140), (30, 160)])

        XCTAssertEqual(values.values(from: 10, to: 20), series([(10, 120), (20, 140)]))
        XCTAssertEqual(values.mean(from: 10, to: 30), 140)
        XCTAssertNil(values.mean(from: 40, to: 50))
    }

    func testLongestGapCountsTheEdgesOfTheWindow() {
        let values = series([(10, 1), (15, 1), (40, 1), (45, 1)])

        XCTAssertEqual(values.longestGap(from: 10, to: 45), 25)
        // Vor der ersten Messung im Fenster.
        XCTAssertEqual(values.longestGap(from: 0, to: 15), 10)
        // Nach der letzten.
        XCTAssertEqual(values.longestGap(from: 40, to: 100), 55)
        // Ohne Messung: das ganze Fenster.
        XCTAssertEqual(values.longestGap(from: 50, to: 80), 30)
        XCTAssertEqual(values.longestGap(from: 80, to: 50), 0)
    }

    func testInterpolationBetweenNeighbours() {
        let distance = series([(0, 0), (10, 30), (20, 50)])

        XCTAssertEqual(distance.interpolated(at: 5, tolerance: 60), 15)
        XCTAssertEqual(distance.interpolated(at: 10, tolerance: 60), 30)
        XCTAssertEqual(distance.interpolated(at: 15, tolerance: 60), 40)
    }

    func testInterpolationNeedsANearNeighbour() {
        let distance = series([(0, 0), (200, 600)])

        // Mitten in einer langen Lücke ohne Messung in der Nähe.
        XCTAssertNil(distance.interpolated(at: 100, tolerance: 60))
        // Nahe an einer Seite reicht.
        XCTAssertEqual(distance.interpolated(at: 50, tolerance: 60), 150)
        XCTAssertEqual(distance.interpolated(at: 150, tolerance: 60), 450)
    }

    func testInterpolationAtTheEdges() {
        let distance = series([(100, 300), (110, 330)])

        XCTAssertEqual(distance.interpolated(at: 130, tolerance: 60), 330)
        XCTAssertNil(distance.interpolated(at: 200, tolerance: 60))
        XCTAssertEqual(distance.interpolated(at: 60, tolerance: 60), 300)
        XCTAssertNil(distance.interpolated(at: 10, tolerance: 60))
        XCTAssertNil([TimedValue]().interpolated(at: 10, tolerance: 60))
    }
}
