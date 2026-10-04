import XCTest
import HealthKit
@testable import SwimInstructorCore

/// Die eigene Logik des Ruderns; die allgemeinen Prüfungen laufen in `SportModuleConformanceTests`.
final class RowingModuleTests: XCTestCase {
    private let module = RowingModule()

    private func estimate(_ workouts: [Workout]) -> [PerformanceEstimate] {
        module.estimatePerformance(PerformanceEstimationContext(
            sport: SportID.rowing, now: TestFixtures.now, workouts: workouts, known: ResolvedPerformance(profile: .empty, estimates: [])
        ))
    }

    func testTwoKilometerTimeComesFromTheFastestSessionOfAtLeast2000Meters() {
        let workouts = [
            TestFixtures.workout(.rowing, daysAgo: 1, minutes: 9, meters: 2000),
            TestFixtures.workout(.rowing, daysAgo: 3, minutes: 40, meters: 10_000),
            // Zu kurz für eine Schätzung, auch wenn sie schneller war.
            TestFixtures.workout(.rowing, daysAgo: 5, minutes: 3, meters: 1000)
        ]

        XCTAssertEqual(estimate(workouts), [PerformanceEstimate(metric: .twoKilometerRowingTime, value: 480, source: .estimated)])
    }

    func testNoEstimateWithoutDistance() {
        XCTAssertEqual(estimate([TestFixtures.workout(.rowing, daysAgo: 1, minutes: 30, meters: nil)]), [])
    }

    func testFiveHeartRateZonesFromTheThresholdHeartRate() {
        let zones = module.zoneSchemes.first?.zones(basisValue: 170).zones
        XCTAssertEqual(zones?.count, 5)
        XCTAssertEqual(zones?.first?.maximum, 136)
    }

    func testStandardRegistryFindsRowingWorkoutsAndPlansInMinutes() {
        XCTAssertEqual(SportRegistry.standard.module(forActivityType: HKWorkoutActivityType.rowing)?.id, SportID.rowing)
        XCTAssertEqual(SportRegistry.standard.module(for: SportID.rowing)?.planUnit, PlanUnit.minutes)
        XCTAssertEqual(SportRegistry.standard.statistics(for: SportID.rowing).first?.metric, StatisticMetric.duration)
    }
}
