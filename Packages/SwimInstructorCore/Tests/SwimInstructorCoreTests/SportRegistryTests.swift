import XCTest
import HealthKit
@testable import SwimInstructorCore

final class SportRegistryTests: XCTestCase {
    func testStandardRegistryHasTheThreeTriathlonSportsInOrder() {
        XCTAssertEqual(SportRegistry.standard.ids, [SportID.swim, .bike, .run])
    }

    func testLookupFindsModulesAndIgnoresUnknownIDs() {
        XCTAssertEqual(SportRegistry.standard.module(for: "run")?.displayName, "Laufen")
        XCTAssertNil(SportRegistry.standard.module(for: "kayak"))
    }

    func testDuplicateIDIsRejected() {
        XCTAssertThrowsError(try SportRegistry(modules: [SwimModule(), SwimModule()])) { error in
            XCTAssertEqual(error as? SportRegistry.Problem, .duplicate(.swim))
        }
    }

    func testIncompleteModulesAreRejected() {
        XCTAssertThrowsError(try SportRegistry(modules: [StubModule(id: "Swim-1")])) { error in
            XCTAssertEqual(error as? SportRegistry.Problem, .malformedID("Swim-1"))
        }
        XCTAssertThrowsError(try SportRegistry(modules: [StubModule(id: "yoga", displayName: "  ")])) { error in
            XCTAssertEqual(error as? SportRegistry.Problem, .missingDisplayName("yoga"))
        }
        XCTAssertThrowsError(try SportRegistry(modules: [StubModule(id: "yoga", symbolName: "")])) { error in
            XCTAssertEqual(error as? SportRegistry.Problem, .missingSymbol("yoga"))
        }
        XCTAssertThrowsError(try SportRegistry(modules: [StubModule(id: "yoga", measures: [])])) { error in
            XCTAssertEqual(error as? SportRegistry.Problem, .noMeasures("yoga"))
        }
    }

    func testInvalidLoadFactorAndSharedActivityTypeAreRejected() {
        for factor in [0, -1, Double.infinity, Double.nan] {
            XCTAssertThrowsError(try SportRegistry(modules: [StubModule(id: "yoga", loadFactor: factor)])) { error in
                XCTAssertEqual(error as? SportRegistry.Problem, .invalidLoadFactor("yoga"), "\(factor)")
            }
        }
        let alsoSwimming = StubModule(id: "open_water", health: SportHealthMapping(activityTypes: [.swimming], distance: nil))
        XCTAssertThrowsError(try SportRegistry(modules: [SwimModule(), alsoSwimming])) { error in
            XCTAssertEqual(error as? SportRegistry.Problem, .sharedActivityType("open_water"))
        }
    }

    func testHealthLookupAndReadTypes() throws {
        let sports = SportRegistry.standard
        XCTAssertEqual(sports.module(forActivityType: .swimming)?.id, .swim)
        XCTAssertEqual(sports.module(forActivityType: .cycling)?.id, .bike)
        XCTAssertEqual(sports.module(forActivityType: .running)?.id, .run)
        XCTAssertNil(sports.module(forActivityType: .yoga))
        XCTAssertEqual(sports.activityTypes, [.swimming, .cycling, .running])

        let readTypes = sports.healthReadTypes
        for identifier: HKQuantityTypeIdentifier in [.distanceSwimming, .swimmingStrokeCount, .distanceCycling, .distanceWalkingRunning, .runningPower] {
            XCTAssertTrue(readTypes.contains(HKObjectType.quantityType(forIdentifier: identifier)!), identifier.rawValue)
        }
        let cyclingPower = try XCTUnwrap(HealthQuantity(identifier: "HKQuantityTypeIdentifierCyclingPower", unit: "W", aggregation: .average).quantityType)
        XCTAssertTrue(readTypes.contains(cyclingPower))
    }

    func testDisplayFallsBackForUnknownSports() {
        XCTAssertEqual(SportRegistry.standard.displayName(for: .bike), "Radfahren")
        XCTAssertEqual(SportRegistry.standard.symbolName(for: .run), "figure.run")
        XCTAssertEqual(SportRegistry.standard.displayName(for: "kayak"), "kayak")
        XCTAssertEqual(SportRegistry.standard.symbolName(for: "kayak"), "figure.mixed.cardio")
    }

    func testSportIDFormat() {
        XCTAssertTrue(SportID("swim").isWellFormed)
        XCTAssertTrue(SportID("open_water2").isWellFormed)
        XCTAssertFalse(SportID("s").isWellFormed)
        XCTAssertFalse(SportID("2swim").isWellFormed)
        XCTAssertFalse(SportID("Swim").isWellFormed)
        XCTAssertFalse(SportID("swim run").isWellFormed)
        XCTAssertFalse(SportID(rawValue: String(repeating: "a", count: 33)).isWellFormed)
    }

    func testSportIDIsAPlainJSONStringAndKeepsUnknownValues() throws {
        let encoded = try JSONEncoder().encode([SportID.bike, "kayak"])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"["bike","kayak"]"#)
        XCTAssertEqual(try JSONDecoder().decode([SportID].self, from: encoded), [.bike, "kayak"])
        XCTAssertEqual(SportID.run.description, "run")
    }

    func testSupportsChecksMeasureAndTarget() {
        let run = RunModule()
        XCTAssertTrue(run.supports(measure: .duration, target: .pacePerKilometer))
        XCTAssertTrue(run.supports(measure: .distance, target: nil))
        XCTAssertFalse(run.supports(measure: .distance, target: .pacePerHundredMeters))
        XCTAssertFalse(run.supports(measure: .repetitions, target: nil))
    }
}

/// Ein absichtlich unvollständiges Modul für die Prüfungen der Registry.
private struct StubModule: SportModule {
    var id: SportID
    var displayName = "Stub"
    var symbolName = "questionmark"
    var measures: Set<StepMeasure> = [.duration]
    var targets: Set<StepTarget> = []
    var health = SportHealthMapping(activityTypes: [.yoga], distance: nil)
    var loadFactor = 1.0
}
