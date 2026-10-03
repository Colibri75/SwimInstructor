import XCTest
@testable import SwimInstructorCore

final class TrainingZonesTests: XCTestCase {
    private typealias Zone = TrainingZones.Zone

    func testProportionalZonesAreSharesOfTheBasis() {
        let scheme = ZoneScheme(target: .heartRateZone, basis: .thresholdHeartRate, bounds: [0.8, 0.9, 1.0])
        let zones = scheme.zones(basisValue: 150)

        XCTAssertEqual(zones.target, .heartRateZone)
        XCTAssertEqual(zones.basis, .thresholdHeartRate)
        XCTAssertEqual(zones.zones, [
            Zone(zone: 1, minimum: nil, maximum: 120),
            Zone(zone: 2, minimum: 120, maximum: 135),
            Zone(zone: 3, minimum: 135, maximum: 150),
            Zone(zone: 4, minimum: 150, maximum: nil)
        ])
    }

    func testPaceZonesAreSharesOfTheSpeedSoZoneOneIsTheSlowest() {
        let scheme = ZoneScheme(target: .pacePerKilometer, basis: .thresholdPacePerKilometer, scale: .inversePace, bounds: [0.8, 1.0])
        XCTAssertEqual(scheme.zones(basisValue: 300).zones, [
            Zone(zone: 1, minimum: 375, maximum: nil),
            Zone(zone: 2, minimum: 300, maximum: 375),
            Zone(zone: 3, minimum: nil, maximum: 300)
        ])
    }

    func testBoundsMustBePositiveAndStrictlyIncreasing() {
        func scheme(_ bounds: [Double]) -> ZoneScheme {
            ZoneScheme(target: .heartRateZone, basis: .maxHeartRate, bounds: bounds)
        }
        XCTAssertTrue(scheme([0.5, 1]).hasValidBounds)
        XCTAssertTrue(scheme([0.9]).hasValidBounds)
        XCTAssertFalse(scheme([]).hasValidBounds)
        XCTAssertFalse(scheme([0, 1]).hasValidBounds)
        XCTAssertFalse(scheme([0.9, 0.8]).hasValidBounds)
        XCTAssertFalse(scheme([0.8, 0.8]).hasValidBounds)
    }

    func testZoneLookup() {
        let zones = ZoneScheme(target: .heartRateZone, basis: .maxHeartRate, bounds: [0.6]).zones(basisValue: 200)
        XCTAssertEqual(zones.zone(1), Zone(zone: 1, minimum: nil, maximum: 120))
        XCTAssertEqual(zones.zone(2), Zone(zone: 2, minimum: 120, maximum: nil))
        XCTAssertNil(zones.zone(3))
    }

    // MARK: - Zonen der echten Sportarten, von Hand nachgerechnet

    private func zones(_ module: any SportModule, _ target: StepTarget, basis: Double) throws -> [Zone] {
        try XCTUnwrap(module.zoneSchemes.first { $0.target == target }, "\(module.id) \(target)").zones(basisValue: basis).zones
    }

    func testSwimPaceZonesFromCSS() throws {
        // CSS 1:45 pro 100 m: Zone 4 von 1:43 bis 1:51, Zone 2 (Grundlage) von 1:59 bis 2:11.
        XCTAssertEqual(try zones(SwimModule(), .pacePerHundredMeters, basis: 105), [
            Zone(zone: 1, minimum: 131, maximum: nil),
            Zone(zone: 2, minimum: 119, maximum: 131),
            Zone(zone: 3, minimum: 111, maximum: 119),
            Zone(zone: 4, minimum: 103, maximum: 111),
            Zone(zone: 5, minimum: nil, maximum: 103)
        ])
    }

    func testBikeZonesFromThresholdHeartRateAndPower() throws {
        XCTAssertEqual(try zones(BikeModule(), .heartRateZone, basis: 160), [
            Zone(zone: 1, minimum: nil, maximum: 130),
            Zone(zone: 2, minimum: 130, maximum: 144),
            Zone(zone: 3, minimum: 144, maximum: 150),
            Zone(zone: 4, minimum: 150, maximum: 160),
            Zone(zone: 5, minimum: 160, maximum: nil)
        ])
        // Coggan mit FTP 250 W: 55, 75, 90, 105, 120 %.
        XCTAssertEqual(try zones(BikeModule(), .power, basis: 250), [
            Zone(zone: 1, minimum: nil, maximum: 138),
            Zone(zone: 2, minimum: 138, maximum: 188),
            Zone(zone: 3, minimum: 188, maximum: 225),
            Zone(zone: 4, minimum: 225, maximum: 263),
            Zone(zone: 5, minimum: 263, maximum: 300),
            Zone(zone: 6, minimum: 300, maximum: nil)
        ])
    }

    func testRunZonesFromThresholdHeartRateAndPace() throws {
        XCTAssertEqual(try zones(RunModule(), .heartRateZone, basis: 165), [
            Zone(zone: 1, minimum: nil, maximum: 140),
            Zone(zone: 2, minimum: 140, maximum: 149),
            Zone(zone: 3, minimum: 149, maximum: 157),
            Zone(zone: 4, minimum: 157, maximum: 165),
            Zone(zone: 5, minimum: 165, maximum: nil)
        ])
        // Schwelle 4:50 pro km: Grundlage (Zone 2) von 5:30 bis 6:12.
        XCTAssertEqual(try zones(RunModule(), .pacePerKilometer, basis: 290), [
            Zone(zone: 1, minimum: 372, maximum: nil),
            Zone(zone: 2, minimum: 330, maximum: 372),
            Zone(zone: 3, minimum: 309, maximum: 330),
            Zone(zone: 4, minimum: 287, maximum: 309),
            Zone(zone: 5, minimum: nil, maximum: 287)
        ])
    }

    func testSwimHeartRateZonesUseTheMaximumHeartRate() throws {
        XCTAssertEqual(try zones(SwimModule(), .heartRateZone, basis: 188).map(\.maximum), [113, 132, 150, 169, nil])
    }

    func testZonesLeaveOutOpenBoundsInJSON() throws {
        let zones = ZoneScheme(target: .heartRateZone, basis: .maxHeartRate, bounds: [0.6]).zones(basisValue: 200)
        let json = try JSONSerialization.jsonObject(with: AthleteStateSnapshot.jsonEncoder().encode(zones)) as? [String: Any]
        let list = try XCTUnwrap(json?["zones"] as? [[String: Any]])
        XCTAssertEqual(Set(list[0].keys), ["zone", "maximum"])
        XCTAssertEqual(Set(list[1].keys), ["zone", "minimum"])
        XCTAssertEqual(json?["basis"] as? String, "max_heart_rate")
        XCTAssertEqual(json?["target"] as? String, "heart_rate_zone")
    }

    func testOnlyMaximalTestsCountAsTested() {
        XCTAssertEqual(PerformanceTest(id: "a_test", displayName: "A", produces: [], maximalEffort: true, durationMinutes: 1).resultSource, .tested)
        XCTAssertEqual(PerformanceTest(id: "a_test", displayName: "A", produces: [], maximalEffort: false, durationMinutes: 1).resultSource, .estimated)
    }
}
