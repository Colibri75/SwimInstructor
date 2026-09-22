import XCTest
import HealthKit
@testable import SwimInstructorCore

final class SwimWorkoutRepositoryTests: XCTestCase {
    func testMapComputesPaceAndKeepsRawValues() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(1800) // 30 Minuten
        let workout = HKWorkout(
            activityType: .swimming,
            start: start,
            end: end,
            workoutEvents: nil,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        )

        let swimWorkout = HealthKitSwimWorkoutRepository.map(
            workout: workout,
            distanceMeters: 1500,
            totalStrokeCount: 900,
            averageHeartRate: 132
        )

        XCTAssertEqual(swimWorkout.id, workout.uuid)
        XCTAssertEqual(swimWorkout.duration, 1800)
        XCTAssertEqual(swimWorkout.totalDistanceMeters, 1500)
        XCTAssertEqual(swimWorkout.averageHeartRate, 132)
        // 1800s / (1500m / 100) = 120 s/100m
        XCTAssertEqual(swimWorkout.averagePaceSecondsPer100m ?? -1, 120, accuracy: 0.001)
    }

    func testMapWithoutDistanceHasNoPaceOrSwolf() {
        let workout = HKWorkout(
            activityType: .swimming,
            start: Date(),
            end: Date().addingTimeInterval(600),
            workoutEvents: nil,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        )

        let swimWorkout = HealthKitSwimWorkoutRepository.map(
            workout: workout,
            distanceMeters: nil,
            totalStrokeCount: nil,
            averageHeartRate: nil
        )

        XCTAssertNil(swimWorkout.averagePaceSecondsPer100m)
        XCTAssertNil(swimWorkout.approximateAverageSwolf)
    }

    func testLapCountCountsOnlyLapEvents() {
        let start = Date()
        let events = [
            HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: start, duration: 30), metadata: nil),
            HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: start.addingTimeInterval(30), duration: 30), metadata: nil),
            HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: start.addingTimeInterval(60), duration: 10), metadata: nil)
        ]
        let workout = HKWorkout(
            activityType: .swimming,
            start: start,
            end: start.addingTimeInterval(70),
            workoutEvents: events,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        )

        XCTAssertEqual(HealthKitSwimWorkoutRepository.lapCount(from: workout), 2)
    }

    func testLapCountIsNilWhenNoLapEvents() {
        let workout = HKWorkout(
            activityType: .swimming,
            start: Date(),
            end: Date().addingTimeInterval(600),
            workoutEvents: nil,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: nil
        )

        XCTAssertNil(HealthKitSwimWorkoutRepository.lapCount(from: workout))
    }

    func testApproximateSwolfAveragesTimeAndStrokesPerLap() {
        let swimWorkout = SwimWorkout(
            id: UUID(),
            startDate: Date(),
            endDate: Date().addingTimeInterval(600),
            duration: 600,
            totalDistanceMeters: 1000,
            lapCount: 20,
            totalStrokeCount: 400,
            averageHeartRate: nil
        )

        // 600s/20 Bahnen = 30s/Bahn, 400 Züge/20 Bahnen = 20 Züge/Bahn -> SWOLF 50
        XCTAssertEqual(swimWorkout.approximateAverageSwolf ?? -1, 50, accuracy: 0.001)
    }
}
