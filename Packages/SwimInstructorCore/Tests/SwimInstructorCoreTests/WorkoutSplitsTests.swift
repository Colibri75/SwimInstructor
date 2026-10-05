import XCTest
import HealthKit
@testable import SwimInstructorCore

final class WorkoutSplitsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func lap(_ from: TimeInterval, _ to: TimeInterval, _ style: SwimStrokeStyle? = .freestyle) -> WorkoutEventInterval {
        WorkoutEventInterval(kind: .lap, start: at(from), end: at(to), strokeStyle: style)
    }

    private func sample(_ from: TimeInterval, _ to: TimeInterval, _ value: Double) -> WorkoutQuantitySample {
        WorkoutQuantitySample(start: at(from), end: at(to), value: value)
    }

    func testSwimSetsGroupLapsAndMeasureRest() {
        // Set 1: zwei Bahnen Freistil, 30 s Pause, Set 2: eine Bahn Brust und eine Freistil.
        let data = WorkoutSplitData(
            events: [
                WorkoutEventInterval(kind: .segment, start: at(0), end: at(60)),
                WorkoutEventInterval(kind: .segment, start: at(90), end: at(160)),
                lap(0, 28), lap(28, 60),
                lap(90, 125, .breaststroke), lap(125, 160)
            ],
            distance: [sample(0, 28, 25), sample(28, 60, 25), sample(90, 125, 25), sample(125, 160, 25)],
            strokes: [sample(0, 28, 14), sample(28, 60, 15), sample(90, 125, 10), sample(125, 160, 16)]
        )
        let heartRates = [HeartRateSample(date: at(10), beatsPerMinute: 130), HeartRateSample(date: at(50), beatsPerMinute: 150)]

        let report = WorkoutSplitBuilder.report(data: data, heartRates: heartRates, workoutStart: at(0), workoutEnd: at(200))

        XCTAssertEqual(report.sets.count, 2)
        XCTAssertTrue(report.laps.isEmpty)
        XCTAssertTrue(report.distanceSplits.isEmpty)

        let first = report.sets[0]
        XCTAssertNil(first.restBefore)
        XCTAssertEqual(first.summary.number, 1)
        XCTAssertEqual(first.summary.duration, 60)
        XCTAssertEqual(first.summary.distanceMeters, 50)
        XCTAssertEqual(first.summary.strokes, 29)
        XCTAssertEqual(first.summary.strokeStyle, .freestyle)
        XCTAssertEqual(first.summary.averageHeartRate, 140)
        XCTAssertEqual(first.laps.map(\.number), [1, 2])
        XCTAssertEqual(first.laps.map(\.duration), [28, 32])
        XCTAssertEqual(first.laps.map(\.strokes), [14, 15])

        let second = report.sets[1]
        XCTAssertEqual(second.restBefore, 30)
        XCTAssertEqual(second.summary.strokeStyle, .mixed)
        XCTAssertEqual(second.laps.map(\.number), [1, 2])
        XCTAssertEqual(second.laps.first?.strokeStyle, .breaststroke)
    }

    func testLapsWithoutDistanceSamplesUsePoolLength() {
        let data = WorkoutSplitData(events: [lap(0, 30), lap(30, 62)], lapLengthMeters: 25)

        let report = WorkoutSplitBuilder.report(data: data, workoutStart: at(0), workoutEnd: at(62))

        XCTAssertTrue(report.sets.isEmpty)
        XCTAssertEqual(report.laps.map(\.distanceMeters), [25, 25])
        XCTAssertEqual(report.laps.map(\.number), [1, 2])
        XCTAssertEqual(report.laps.first?.speed ?? 0, 25.0 / 30, accuracy: 0.0001)
    }

    func testLapsOutsideSetsStayInLapList() {
        let data = WorkoutSplitData(events: [
            WorkoutEventInterval(kind: .segment, start: at(0), end: at(60)),
            lap(0, 30), lap(30, 60), lap(100, 130)
        ])

        let report = WorkoutSplitBuilder.report(data: data, workoutStart: at(0), workoutEnd: at(130))

        XCTAssertEqual(report.sets.first?.laps.count, 2)
        XCTAssertEqual(report.laps.map(\.start), [at(100)])
        XCTAssertEqual(report.laps.map(\.number), [1])
    }

    func testKilometerSplitsInterpolateAndSkipPauses() {
        // 2,3 km in 100-m-Messungen alle 30 s; zwischen 450 und 510 s pausiert.
        var distance: [WorkoutQuantitySample] = []
        var time: TimeInterval = 0
        for _ in 0..<23 {
            if time == 450 { time = 510 }
            distance.append(sample(time, time + 30, 100))
            time += 30
        }
        let data = WorkoutSplitData(
            events: [
                WorkoutEventInterval(kind: .pause, start: at(450), end: at(450)),
                WorkoutEventInterval(kind: .resume, start: at(510), end: at(510))
            ],
            distance: distance
        )

        let report = WorkoutSplitBuilder.report(
            data: data, workoutStart: at(0), workoutEnd: at(time), splitLengthMeters: 1000
        )

        XCTAssertEqual(report.splitLengthMeters, 1000)
        XCTAssertEqual(report.distanceSplits.count, 3)
        XCTAssertEqual(report.distanceSplits[0].duration, 300, accuracy: 0.001)
        XCTAssertEqual(report.distanceSplits[0].distanceMeters, 1000)
        // Der zweite Kilometer enthält die Pause, die nicht zählt.
        XCTAssertEqual(report.distanceSplits[1].end.timeIntervalSince(report.distanceSplits[1].start), 360, accuracy: 0.001)
        XCTAssertEqual(report.distanceSplits[1].duration, 300, accuracy: 0.001)
        XCTAssertEqual(report.distanceSplits[2].distanceMeters ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(report.distanceSplits[2].duration, 90, accuracy: 0.001)
    }

    func testShortRemainderIsDropped() {
        let data = WorkoutSplitData(distance: [sample(0, 300, 1000), sample(300, 310, 20)])

        let report = WorkoutSplitBuilder.report(data: data, workoutStart: at(0), workoutEnd: at(310), splitLengthMeters: 1000)

        XCTAssertEqual(report.distanceSplits.count, 1)
    }

    func testSplitLengthFollowsPrimaryField() {
        XCTAssertNil(WorkoutSplitBuilder.splitLength(for: .pacePerHundredMeters))
        XCTAssertEqual(WorkoutSplitBuilder.splitLength(for: .pacePerKilometer), 1000)
        XCTAssertEqual(WorkoutSplitBuilder.splitLength(for: .speed), 5000)
    }

    func testPauseWithoutResumeRunsToEnd() {
        let pauses = WorkoutSplitBuilder.pauseIntervals(
            [WorkoutEventInterval(kind: .pause, start: at(100), end: at(100))], workoutEnd: at(160)
        )
        XCTAssertEqual(pauses, [DateInterval(start: at(100), end: at(160))])
    }

    func testHealthEventsKeepLapsSegmentsPausesAndStrokeStyle() {
        let events = [
            HKWorkoutEvent(
                type: .lap, dateInterval: DateInterval(start: at(0), duration: 30),
                metadata: [HKMetadataKeySwimmingStrokeStyle: NSNumber(value: HKSwimmingStrokeStyle.backstroke.rawValue)]
            ),
            HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: at(0), duration: 60), metadata: nil),
            HKWorkoutEvent(type: .motionPaused, dateInterval: DateInterval(start: at(60), duration: 0), metadata: nil),
            HKWorkoutEvent(type: .motionResumed, dateInterval: DateInterval(start: at(70), duration: 0), metadata: nil),
            HKWorkoutEvent(type: .marker, dateInterval: DateInterval(start: at(80), duration: 0), metadata: nil)
        ]

        let mapped = HealthKitWorkoutSplitRepository.events(from: events)

        XCTAssertEqual(mapped.map(\.kind), [.lap, .segment, .pause, .resume])
        XCTAssertEqual(mapped.first?.strokeStyle, .backstroke)
        XCTAssertNil(mapped[1].strokeStyle)
    }

    func testPoolLengthComesFromMetadata() {
        let workout = HKWorkout(
            activityType: .swimming, start: at(0), end: at(600), workoutEvents: nil, totalEnergyBurned: nil,
            totalDistance: nil, metadata: [
                HKMetadataKeyLapLength: HKQuantity(unit: .meter(), doubleValue: 50),
                // Ohne Becken als Ort lehnt HealthKit eine Beckenlänge ab.
                HKMetadataKeySwimmingLocationType: NSNumber(value: HKWorkoutSwimmingLocationType.pool.rawValue)
            ]
        )
        XCTAssertEqual(HealthKitWorkoutSplitRepository.data(from: workout).lapLengthMeters, 50)
    }

    func testFormatting() {
        XCTAssertEqual(WorkoutSplitFormatting.duration(28.4), "0:28")
        XCTAssertEqual(WorkoutSplitFormatting.duration(3730), "1:02:10")
        XCTAssertEqual(WorkoutSplitFormatting.distance(200, field: .pacePerHundredMeters), "200 m")
        XCTAssertEqual(WorkoutSplitFormatting.distance(1500, field: .pacePerHundredMeters), "1.500 m")
        XCTAssertEqual(WorkoutSplitFormatting.distance(1000, field: .pacePerKilometer), "1,00 km")
        XCTAssertEqual(WorkoutSplitFormatting.distance(400, field: .speed), "400 m")
        XCTAssertEqual(WorkoutSplitFormatting.speed(100.0 / 112, field: .pacePerHundredMeters), "1:52 /100 m")
        XCTAssertEqual(WorkoutSplitFormatting.speed(1000.0 / 312, field: .pacePerKilometer), "5:12 /km")
        XCTAssertEqual(WorkoutSplitFormatting.speed(7.9, field: .speed), "28,4 km/h")
        XCTAssertNil(WorkoutSplitFormatting.speed(nil, field: .speed))
        XCTAssertEqual(WorkoutSplitFormatting.rest(30), "Pause 0:30")

        let split = WorkoutSplit(
            number: 1, start: at(0), end: at(112), duration: 112, distanceMeters: 100, strokes: 62,
            strokeStyle: .freestyle, averageHeartRate: 141.6
        )
        XCTAssertEqual(
            WorkoutSplitFormatting.detail(split, field: .pacePerHundredMeters),
            "100 m · 1:52 /100 m · Freistil · 62 Züge · 142 bpm"
        )
        XCTAssertEqual(WorkoutSplitFormatting.setTitle(2, field: .pacePerHundredMeters), "Set 2")
        XCTAssertEqual(WorkoutSplitFormatting.lapTitle(3, field: .pacePerKilometer), "Runde 3")

        let kilometer = WorkoutSplit(number: 3, start: at(0), end: at(300), duration: 300, distanceMeters: 1000)
        XCTAssertEqual(WorkoutSplitFormatting.splitTitle(kilometer, length: 1000), "Kilometer 3")
        let lastKilometer = WorkoutSplit(number: 4, start: at(0), end: at(90), duration: 90, distanceMeters: 300)
        XCTAssertEqual(WorkoutSplitFormatting.splitTitle(lastKilometer, length: 1000), "km 3–3,3")
        let bike = WorkoutSplit(number: 3, start: at(0), end: at(600), duration: 600, distanceMeters: 5000)
        XCTAssertEqual(WorkoutSplitFormatting.splitTitle(bike, length: 5000), "km 10–15")
        XCTAssertEqual(WorkoutSplitFormatting.splitsTitle(length: 5000), "Teilstrecken je 5 km")
    }
}
