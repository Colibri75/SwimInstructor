import XCTest
import HealthKit
@testable import SwimInstructorCore

/// Erfundene Sportart nur für Tests, mit anderer Logik als die drei echten: geplant nach Zeit, Intensität nach
/// Schlagzahl. Läuft durch dieselben Prüfungen wie Schwimmen, Rad und Laufen. Bricht sie, ist der Kern nicht
/// mehr allgemein genug für weitere Sportarten.
struct RowingTestModule: SportModule {
    let id: SportID = "rowing"
    let displayName = "Rudern"
    let symbolName = "figure.rower"
    let measures: Set<StepMeasure> = [.duration, .distance]
    let targets: Set<StepTarget> = [.strokeRate, .power, .heartRateZone]
    // Anders als die echten Sportarten: ohne Strecke aus Health, nur mit eigenem Messwert.
    let health = SportHealthMapping(
        activityTypes: [.rowing],
        distance: nil,
        metrics: ["average_power": HealthQuantity(.runningPower, unit: "W", aggregation: .average)]
    )
    let loadFactor = 0.9
    let goalSpeedRange: ClosedRange<Double> = 0.5...7
}

/// Prüfungen, die jedes Modul bestehen muss. Jeder Umbauschritt hängt hier seine neuen Anforderungen an
/// (Health-Umwandlung, Belastung, Fortschritt, Statistik); sie gelten dann automatisch für jede Sportart.
final class SportModuleConformanceTests: XCTestCase {
    /// Die echten Module plus die Test-Sportart.
    private var allModules: [any SportModule] {
        SportRegistry.standard.modules + [RowingTestModule() as any SportModule]
    }

    func testEveryModuleIsCompleteAndRegistrable() throws {
        let registry = try SportRegistry(modules: allModules)
        XCTAssertEqual(registry.ids.count, SportRegistry.standard.ids.count + 1)
        for module in allModules {
            XCTAssertTrue(module.id.isWellFormed, "\(module.id)")
            XCTAssertFalse(module.displayName.isEmpty, "\(module.id)")
            XCTAssertFalse(module.symbolName.isEmpty, "\(module.id)")
            XCTAssertFalse(module.measures.isEmpty, "\(module.id)")
            XCTAssertFalse(module.targets.isEmpty, "\(module.id): ohne Ziel kann kein Schritt eine Intensität vorgeben")
        }
    }

    func testEveryModuleCanBePlannedWithoutTargetAndWithEachOfItsTargets() {
        for module in allModules {
            for measure in module.measures {
                XCTAssertTrue(module.supports(measure: measure, target: nil), "\(module.id) \(measure)")
                for target in module.targets {
                    XCTAssertTrue(module.supports(measure: measure, target: target), "\(module.id) \(measure) \(target)")
                }
            }
        }
    }

    func testEveryModuleIsFoundByItsID() throws {
        let registry = try SportRegistry(modules: allModules)
        for module in allModules {
            XCTAssertEqual(registry.module(for: module.id)?.displayName, module.displayName)
        }
    }

    // MARK: - T1: Health und Belastung

    func testEveryHealthQuantityExistsAndFitsItsUnit() {
        for module in allModules {
            for quantity in module.health.quantities {
                guard let type = quantity.quantityType else {
                    XCTFail("\(module.id): \(quantity.identifier) gibt es in HealthKit nicht")
                    continue
                }
                XCTAssertTrue(type.is(compatibleWith: quantity.healthUnit), "\(module.id): \(quantity.identifier) in \(quantity.unit)")
                XCTAssertTrue(module.health.readTypes.contains(type), "\(module.id): \(quantity.identifier)")
            }
            if let distance = module.health.distance {
                XCTAssertEqual(distance.aggregation, .sum, "\(module.id): Strecke wird summiert")
                XCTAssertEqual(distance.healthUnit, .meter(), "\(module.id): Strecke in Metern")
            }
        }
    }

    func testEveryModuleIsFoundByItsHealthActivityTypes() throws {
        let registry = try SportRegistry(modules: allModules)
        for module in allModules {
            XCTAssertFalse(module.health.activityTypes.isEmpty, "\(module.id): ohne Workout-Art kommt nichts aus Health")
            for activityType in module.health.activityTypes {
                XCTAssertEqual(registry.module(forActivityType: activityType)?.id, module.id)
            }
        }
    }

    func testEveryModuleTurnsAHealthWorkoutIntoAWorkoutOfItsSport() throws {
        let registry = try SportRegistry(modules: allModules)
        let start = Date(timeIntervalSince1970: 1_000_000)
        for module in allModules {
            let activityType = try XCTUnwrap(module.health.activityTypes.first)
            let healthWorkout = HKWorkout(
                activityType: activityType, start: start, end: start.addingTimeInterval(2400),
                workoutEvents: nil, totalEnergyBurned: nil, totalDistance: nil, metadata: nil
            )
            let found = try XCTUnwrap(registry.module(forActivityType: healthWorkout.workoutActivityType))
            let metrics = Dictionary(uniqueKeysWithValues: found.health.metrics.keys.map { ($0, 1.0) })
            let workout = HealthKitWorkoutRepository.map(
                workout: healthWorkout, sport: found.id, distanceMeters: found.health.distance == nil ? nil : 5000,
                averageHeartRate: 140, activeEnergyKilocalories: 400, metrics: metrics
            )
            XCTAssertEqual(workout.sport, module.id)
            XCTAssertEqual(workout.duration, 2400)
            XCTAssertEqual(Set(workout.metrics.keys), Set(module.health.metrics.keys))
        }
    }

    func testEveryModuleHasAPositiveLoadAndLoadGrowsWithDuration() {
        let calculator = TrainingLoadCalculator(registry: try! SportRegistry(modules: allModules))
        for module in allModules {
            XCTAssertGreaterThan(module.loadFactor, 0, "\(module.id)")
            let short = Workout(id: UUID(), sport: module.id, startDate: Date(), endDate: Date(), duration: 1800)
            let long = Workout(id: UUID(), sport: module.id, startDate: Date(), endDate: Date(), duration: 3600)
            XCTAssertGreaterThan(calculator.load(of: long), calculator.load(of: short), "\(module.id)")
        }
    }

    // MARK: - T2: Ziel

    func testEveryModuleHasAGoalSpeedWindowThatAcceptsTypicalGoals() throws {
        let registry = try SportRegistry(modules: allModules)
        for module in allModules {
            let range = module.goalSpeedRange
            XCTAssertGreaterThan(range.lowerBound, 0, "\(module.id)")
            XCTAssertGreaterThan(range.upperBound, range.lowerBound * 2, "\(module.id)")
            // Eine Stunde mit mittlerem Tempo ist ein plausibles Ziel, eine Minute für dieselbe Strecke nicht.
            let meters = (range.lowerBound + range.upperBound) / 2 * 3600
            XCTAssertTrue(registry.isPlausibleGoal(sport: module.id, distanceMeters: meters, durationSeconds: 3600), "\(module.id)")
            XCTAssertFalse(registry.isPlausibleGoal(sport: module.id, distanceMeters: meters, durationSeconds: 60), "\(module.id)")
        }
    }

    func testEveryModuleCanBeAGoalDisciplineAndCarryTheWholeEmphasis() throws {
        let registry = try SportRegistry(modules: allModules)
        for module in allModules {
            let goal = TrainingGoal(
                disciplines: [.init(sport: module.id, distanceMeters: 10_000)],
                targetDate: Date().addingTimeInterval(90 * 86_400),
                trainingDaysPerWeek: 4,
                weeklyHours: 5,
                emphasis: [.init(sport: module.id, percent: 100)]
            )
            XCTAssertNil(goal.problem(now: Date(), registry: registry), "\(module.id)")
        }
    }

    func testTestSportReallyHasItsOwnLogic() {
        // Rudern plant nach Schlagzahl, was keine der echten Sportarten kann: Der Test beweist nur dann etwas,
        // wenn die Test-Sportart nicht bloß eine Kopie einer echten ist.
        XCTAssertTrue(RowingTestModule().targets.contains(.strokeRate))
        XCTAssertFalse(SportRegistry.standard.modules.contains { $0.targets.contains(.strokeRate) })
    }
}
