import XCTest
import HealthKit
@testable import SwimAppCore

final class HealthKitManagerTests: XCTestCase {
    func testReadTypesIncludeSwimWorkoutsAndVitals() {
        let types = HealthKitManager.readTypes

        XCTAssertTrue(types.contains(HKObjectType.workoutType()))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .heartRate)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .restingHeartRate)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!))
        XCTAssertTrue(types.contains(HKObjectType.quantityType(forIdentifier: .distanceSwimming)!))
        XCTAssertTrue(types.contains(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!))
    }
}
