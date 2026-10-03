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

    func testGoalSpeedMustStartAboveZeroAndBeFinite() {
        for range: ClosedRange<Double> in [0...1, -1...1, 1...Double.infinity] {
            XCTAssertThrowsError(try SportRegistry(modules: [StubModule(id: "yoga", goalSpeedRange: range)])) { error in
                XCTAssertEqual(error as? SportRegistry.Problem, .invalidGoalSpeed("yoga"), "\(range)")
            }
        }
    }

    func testPlausibleGoalUsesTheModulesSpeedWindow() {
        let sports = SportRegistry.standard
        XCTAssertTrue(sports.isPlausibleGoal(sport: .swim, distanceMeters: 3800, durationSeconds: 3600))
        XCTAssertFalse(sports.isPlausibleGoal(sport: .swim, distanceMeters: 3800, durationSeconds: 600))
        XCTAssertTrue(sports.isPlausibleGoal(sport: .run, distanceMeters: 10_000, durationSeconds: 3000))
        XCTAssertFalse(sports.isPlausibleGoal(sport: .run, distanceMeters: 10_000, durationSeconds: 600))
        XCTAssertTrue(sports.isPlausibleGoal(sport: .bike, distanceMeters: 40_000, durationSeconds: 4800))
        XCTAssertFalse(sports.isPlausibleGoal(sport: .bike, distanceMeters: 40_000, durationSeconds: 0))
        XCTAssertFalse(sports.isPlausibleGoal(sport: "kayak", distanceMeters: 1000, durationSeconds: 600))
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

    // MARK: - Leistungsprofil

    private let lactate = PerformanceMetricDefinition(metric: "lactate_power", displayName: "Laktatleistung", unit: "W", plausibleRange: 50...500)

    private func assertRejected(_ module: StubModule, as problem: SportRegistry.Problem, _ message: String, line: UInt = #line) {
        XCTAssertThrowsError(try SportRegistry(modules: [module]), message, line: line) { error in
            XCTAssertEqual(error as? SportRegistry.Problem, problem, message, line: line)
        }
    }

    func testInvalidPerformanceMetricsAreRejected() {
        let invalid: [(String, [PerformanceMetricDefinition])] = [
            ("Kennung", [PerformanceMetricDefinition(metric: "Lactate", displayName: "L", unit: "W", plausibleRange: 1...2)]),
            ("für alle Sportarten", [.maxHeartRate]),
            ("doppelt", [lactate, lactate]),
            ("ohne Namen", [PerformanceMetricDefinition(metric: "lactate", displayName: "", unit: "W", plausibleRange: 1...2)]),
            ("ohne Einheit", [PerformanceMetricDefinition(metric: "lactate", displayName: "L", unit: "", plausibleRange: 1...2)]),
            ("Bereich ab 0", [PerformanceMetricDefinition(metric: "lactate", displayName: "L", unit: "W", plausibleRange: 0...2)]),
            ("Bereich offen", [PerformanceMetricDefinition(metric: "lactate", displayName: "L", unit: "W", plausibleRange: 1...Double.infinity)])
        ]
        for (message, metrics) in invalid {
            assertRejected(StubModule(id: "yoga", performanceMetrics: metrics), as: .invalidPerformanceMetric("yoga"), message)
        }
    }

    func testInvalidPerformanceTestsAreRejected() {
        func test(id: String = "ramp", name: String = "Rampe", produces: [PerformanceMetric] = ["lactate_power"], minutes: Int = 20) -> PerformanceTest {
            PerformanceTest(id: id, displayName: name, produces: produces, maximalEffort: true, durationMinutes: minutes)
        }
        let invalid: [(String, [PerformanceTest])] = [
            ("Kennung", [test(id: "Ramp Test")]),
            ("doppelt", [test(), test()]),
            ("ohne Namen", [test(name: "")]),
            ("ohne Ergebnis", [test(produces: [])]),
            ("fremdes Ergebnis", [test(produces: [.maxHeartRate])]),
            ("ohne Dauer", [test(minutes: 0)])
        ]
        for (message, tests) in invalid {
            assertRejected(
                StubModule(id: "yoga", performanceMetrics: [lactate], performanceTests: tests),
                as: .invalidPerformanceTest("yoga"), message
            )
        }
        XCTAssertNoThrow(try SportRegistry(modules: [StubModule(id: "yoga", performanceMetrics: [lactate], performanceTests: [test()])]))
    }

    func testInvalidZoneSchemesAreRejected() {
        let invalid: [(String, ZoneScheme)] = [
            ("fremdes Ziel", ZoneScheme(target: .pacePerKilometer, basis: "lactate_power", bounds: [0.8])),
            ("unbekannter Grundwert", ZoneScheme(target: .power, basis: .thresholdPower, bounds: [0.8])),
            ("ungültige Grenzen", ZoneScheme(target: .power, basis: "lactate_power", bounds: [0.9, 0.8]))
        ]
        for (message, scheme) in invalid {
            assertRejected(
                StubModule(id: "yoga", targets: [.power, .heartRateZone], performanceMetrics: [lactate], zoneSchemes: [scheme]),
                as: .invalidZoneScheme("yoga"), message
            )
        }
        // Pulszonen aus dem Maximalpuls: ein Grundwert für alle Sportarten ist erlaubt.
        let fromMaximum = ZoneScheme(target: .heartRateZone, basis: .maxHeartRate, bounds: [0.7, 0.8])
        XCTAssertNoThrow(try SportRegistry(modules: [StubModule(id: "yoga", targets: [.heartRateZone], zoneSchemes: [fromMaximum])]))
    }

    func testAModuleWithoutProfilePlansByFeelOnly() throws {
        let module = ProfilelessModule()
        let registry = try SportRegistry(modules: [module])
        XCTAssertTrue(module.performanceMetrics.isEmpty)
        XCTAssertTrue(module.performanceTests.isEmpty)
        XCTAssertTrue(module.zoneSchemes.isEmpty)
        let context = PerformanceEstimationContext(
            sport: module.id, now: Date(), workouts: [], known: ResolvedPerformance(profile: .empty, estimates: [], registry: registry)
        )
        XCTAssertTrue(module.estimatePerformance(context).isEmpty)
    }

    func testMetricDefinitionsAreFoundPerSportOrForAllSports() {
        let sports = SportRegistry.standard
        XCTAssertEqual(sports.metricDefinition(.maxHeartRate, sport: nil)?.unit, "bpm")
        XCTAssertNil(sports.metricDefinition(.maxHeartRate, sport: .run), "Maximalpuls gehört zu keiner Sportart")
        XCTAssertEqual(sports.metricDefinition(.criticalSwimPace, sport: .swim)?.unit, "s/100m")
        XCTAssertNil(sports.metricDefinition(.criticalSwimPace, sport: .run))
        XCTAssertEqual(sports.metricDefinition(.thresholdHeartRate, sport: .bike)?.displayName, "Schwellenpuls")
        XCTAssertNil(sports.metricDefinition(.thresholdHeartRate, sport: "kayak"))
        XCTAssertNil(sports.metricDefinition("vo2max", sport: nil))
    }

    func testPerformanceMetricIsAPlainJSONString() throws {
        let encoded = try JSONEncoder().encode([PerformanceMetric.maxHeartRate, "vo2max"])
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), #"["max_heart_rate","vo2max"]"#)
        XCTAssertEqual(try JSONDecoder().decode([PerformanceMetric].self, from: encoded), [.maxHeartRate, "vo2max"])
        XCTAssertEqual(PerformanceMetric.thresholdPower.description, "threshold_power")
        XCTAssertTrue(PerformanceMetric.criticalSwimPace.isWellFormed)
        XCTAssertFalse(PerformanceMetric("Max HR").isWellFormed)
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
    var goalSpeedRange: ClosedRange<Double> = 0.1...1
    var performanceMetrics: [PerformanceMetricDefinition] = []
    var performanceTests: [PerformanceTest] = []
    var zoneSchemes: [ZoneScheme] = []
}

/// Eine Sportart ohne Leistungsprofil: Alles dazu kommt aus den Vorgaben des Protokolls.
private struct ProfilelessModule: SportModule {
    let id: SportID = "yoga"
    let displayName = "Yoga"
    let symbolName = "figure.yoga"
    let measures: Set<StepMeasure> = [.duration]
    let targets: Set<StepTarget> = [.perceivedEffort]
    let health = SportHealthMapping(activityTypes: [.yoga], distance: nil)
    let loadFactor = 0.5
    let goalSpeedRange: ClosedRange<Double> = 0.1...1
}
