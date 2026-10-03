import XCTest
import HealthKit
@testable import SwimInstructorCore

final class WorkoutTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testMetricsAreOpenStringKeys() {
        let workout = Workout(
            id: UUID(), sport: .bike, startDate: start, endDate: start.addingTimeInterval(3600), duration: 3600,
            metrics: [.averagePower: 180, "normalized_power": 195]
        )
        XCTAssertEqual(workout[.averagePower], 180)
        XCTAssertEqual(workout["normalized_power"], 195)
        XCTAssertNil(workout[.strokes])
        XCTAssertNil(workout.distanceMeters)
        XCTAssertEqual(WorkoutMetric.elevationGain.description, "elevation_gain")
        XCTAssertEqual(WorkoutMetric(rawValue: "laps"), .laps)
    }

    func testSwimBridgeIsLossless() {
        let swim = SwimWorkout(
            id: UUID(), startDate: start, endDate: start.addingTimeInterval(1800), duration: 1800,
            totalDistanceMeters: 1500, lapCount: 60, totalStrokeCount: 900, averageHeartRate: 132
        )

        let workout = Workout(swim: swim)

        XCTAssertEqual(workout.sport, .swim)
        XCTAssertEqual(workout.distanceMeters, 1500)
        XCTAssertEqual(workout[.laps], 60)
        XCTAssertEqual(workout[.strokes], 900)
        XCTAssertEqual(SwimWorkout(workout: workout), swim)
    }

    func testSwimBridgeWithoutOptionalValues() {
        let swim = SwimWorkout(
            id: UUID(), startDate: start, endDate: start.addingTimeInterval(600), duration: 600,
            totalDistanceMeters: nil, lapCount: nil, totalStrokeCount: nil, averageHeartRate: nil
        )
        let workout = Workout(swim: swim)
        XCTAssertTrue(workout.metrics.isEmpty)
        XCTAssertEqual(SwimWorkout(workout: workout), swim)
    }

    func testOtherSportsAreNoSwimWorkouts() {
        let run = Workout(id: UUID(), sport: .run, startDate: start, endDate: start, duration: 0, distanceMeters: 5000)
        XCTAssertNil(SwimWorkout(workout: run))
    }

    func testHealthQuantityAndMapping() {
        let unknown = HealthQuantity(identifier: "HKQuantityTypeIdentifierDoesNotExist", unit: "m", aggregation: .sum)
        XCTAssertNil(unknown.quantityType)
        XCTAssertEqual(
            HealthQuantity(.distanceCycling, unit: "m", aggregation: .sum),
            HealthQuantity(identifier: HKQuantityTypeIdentifier.distanceCycling.rawValue, unit: "m", aggregation: .sum)
        )

        let mapping = SportHealthMapping(
            activityTypes: [.cycling],
            distance: HealthQuantity(.distanceCycling, unit: "m", aggregation: .sum),
            metrics: [
                .averagePower: HealthQuantity(.runningPower, unit: "W", aggregation: .average),
                "missing": unknown
            ]
        )
        // Strecke zuerst, dann die übrigen Werte stabil nach Kennung sortiert.
        XCTAssertEqual(mapping.quantities.map(\.identifier), [
            HKQuantityTypeIdentifier.distanceCycling.rawValue,
            "HKQuantityTypeIdentifierDoesNotExist",
            HKQuantityTypeIdentifier.runningPower.rawValue
        ])
        // Was das System nicht kennt, wird nicht angefragt.
        XCTAssertEqual(mapping.readTypes.count, 2)
        XCTAssertEqual(mapping.activityTypes, [.cycling])
        XCTAssertTrue(SportHealthMapping(activityTypes: [], distance: nil).quantities.isEmpty)
    }
}
