import XCTest
import HealthKit
@testable import SwimInstructorCore

final class WorkoutRepositoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testMapKeepsValuesAndAddsLapsAndElevation() {
        let events = [
            HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: start, duration: 300), metadata: nil),
            HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: start.addingTimeInterval(300), duration: 300), metadata: nil),
            HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: start.addingTimeInterval(600), duration: 0), metadata: nil)
        ]
        let workout = HKWorkout(
            activityType: .running, start: start, end: start.addingTimeInterval(3000),
            workoutEvents: events, totalEnergyBurned: nil, totalDistance: nil,
            metadata: [HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: 120)]
        )

        let mapped = HealthKitWorkoutRepository.map(
            workout: workout, sport: .run, distanceMeters: 10_000, averageHeartRate: 150,
            activeEnergyKilocalories: 650, metrics: [.averagePower: 240]
        )

        XCTAssertEqual(mapped.id, workout.uuid)
        XCTAssertEqual(mapped.sport, .run)
        XCTAssertEqual(mapped.startDate, start)
        XCTAssertEqual(mapped.duration, 3000)
        XCTAssertEqual(mapped.distanceMeters, 10_000)
        XCTAssertEqual(mapped.averageHeartRate, 150)
        XCTAssertEqual(mapped.activeEnergyKilocalories, 650)
        XCTAssertEqual(mapped.metrics, [.averagePower: 240, .laps: 2, .elevationGain: 120])
    }

    func testMapWithoutEventsOrMetadataAddsNothing() {
        let workout = HKWorkout(
            activityType: .cycling, start: start, end: start.addingTimeInterval(3600),
            workoutEvents: nil, totalEnergyBurned: nil, totalDistance: nil, metadata: nil
        )
        let mapped = HealthKitWorkoutRepository.map(
            workout: workout, sport: .bike, distanceMeters: nil, averageHeartRate: nil,
            activeEnergyKilocalories: nil, metrics: [:]
        )
        XCTAssertTrue(mapped.metrics.isEmpty)
        XCTAssertNil(mapped.distanceMeters)
    }

    func testCommonQuantitiesFitTheirUnits() throws {
        for quantity in [HealthKitWorkoutRepository.heartRate, HealthKitWorkoutRepository.activeEnergy] {
            let type = try XCTUnwrap(quantity.quantityType)
            XCTAssertTrue(type.is(compatibleWith: quantity.healthUnit), quantity.identifier)
            XCTAssertTrue(HealthKitManager.readTypes.contains(type), quantity.identifier)
        }
    }
}
