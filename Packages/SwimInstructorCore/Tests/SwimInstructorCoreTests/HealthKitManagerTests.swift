import XCTest
import HealthKit
@testable import SwimInstructorCore

final class HealthKitManagerTests: XCTestCase {
    func testReadTypesIncludeSwimWorkoutsAndVitals() {
        let types = HealthKitManager.readTypes

        XCTAssertTrue(types.contains(HKObjectType.workoutType()))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .heartRate)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .restingHeartRate)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .distanceSwimming)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount)!))
        XCTAssertTrue(types.contains(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!))
        // Maximalpuls nach Faustformel (Leistungsprofil).
        XCTAssertTrue(types.contains(HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!))
    }

    func testReadTypesIncludeEverySportModule() {
        let types = HealthKitManager.readTypes

        XCTAssertTrue(types.isSuperset(of: SportRegistry.standard.healthReadTypes))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .distanceCycling)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!))
    }

    func testWorkoutShareTypesCoverWhatTheWatchRecords() {
        let types = HealthKitManager.workoutShareTypes

        XCTAssertTrue(types.contains(HKObjectType.workoutType()))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .distanceSwimming)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .swimmingStrokeCount)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .heartRate)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!))
    }

    func testWorkoutShareTypesCoverRouteRunningAndCycling() {
        let types = HealthKitManager.workoutShareTypes

        XCTAssertEqual(types, SportRegistry.standard.workoutShareTypes)
        XCTAssertTrue(types.contains(HKSeriesType.workoutRoute()))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .distanceCycling)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!))
    }
}
