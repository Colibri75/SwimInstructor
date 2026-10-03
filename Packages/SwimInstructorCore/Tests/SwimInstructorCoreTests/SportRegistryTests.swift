import XCTest
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
}
