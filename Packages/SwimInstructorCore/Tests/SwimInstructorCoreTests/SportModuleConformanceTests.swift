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
    let planUnit = PlanUnit.minutes
    let typicalSpeedMetersPerSecond = 3.5

    /// Eigener Leistungswert, den keine echte Sportart kennt.
    static let twoKilometerTime: PerformanceMetric = "time_2000m"

    let performanceMetrics: [PerformanceMetricDefinition] = [
        .thresholdHeartRate,
        PerformanceMetricDefinition(metric: RowingTestModule.twoKilometerTime, displayName: "2000-m-Zeit", unit: "s", plausibleRange: 330...1200)
    ]
    let performanceTests: [PerformanceTest] = [
        PerformanceTest(
            id: "time_trial_2000m", displayName: "2000-m-Test",
            produces: [RowingTestModule.twoKilometerTime, .thresholdHeartRate], maximalEffort: true, durationMinutes: 8
        )
    ]
    // Anders als die echten Sportarten: nur vier Pulszonen.
    let zoneSchemes: [ZoneScheme] = [ZoneScheme(target: .heartRateZone, basis: .thresholdHeartRate, bounds: [0.80, 0.90, 1.00])]

    /// Die 2000-m-Zeit ohne Test: das schnellste Tempo einer Einheit ab 2000 m, hochgerechnet.
    func estimatePerformance(_ context: PerformanceEstimationContext) -> [PerformanceEstimate] {
        let times = context.workouts.compactMap { workout -> Double? in
            guard let meters = workout.distanceMeters, meters >= 2000, workout.duration > 0 else { return nil }
            return workout.duration / meters * 2000
        }
        guard let fastest = times.min() else { return [] }
        return [PerformanceEstimate(metric: RowingTestModule.twoKilometerTime, value: fastest.rounded(), source: .estimated)]
    }
}

/// Prüfungen, die jedes Modul bestehen muss. Jeder Umbauschritt hängt hier seine neuen Anforderungen an
/// (Health-Umwandlung, Belastung, Fortschritt, Statistik); sie gelten dann automatisch für jede Sportart.
final class SportModuleConformanceTests: XCTestCase {
    /// Die echten Module plus die Test-Sportart. Gibt es Rudern schon als echtes Modul, prüfen die Tests dieses.
    private var allModules: [any SportModule] {
        let real = SportRegistry.standard.modules
        return real.contains { $0.id == RowingTestModule().id } ? real : real + [RowingTestModule() as any SportModule]
    }

    /// Die echten Module außer einem echten Rudern: Gegen sie muss sich die Test-Sportart unterscheiden.
    private var otherRealModules: [any SportModule] {
        SportRegistry.standard.modules.filter { $0.id != RowingTestModule().id }
    }

    func testEveryModuleIsCompleteAndRegistrable() throws {
        let registry = try SportRegistry(modules: allModules)
        XCTAssertEqual(registry.ids, allModules.map(\.id))
        XCTAssertTrue(registry.ids.contains(RowingTestModule().id))
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

    // MARK: - T2b: Leistungsprofil

    func testEveryTestMeasuresValuesOfItsOwnSportAndEveryZoneHasItsBasis() {
        let athlete = Set(PerformanceMetricDefinition.athlete.map(\.metric))
        for module in allModules {
            let metrics = Set(module.performanceMetrics.map(\.metric))
            XCTAssertFalse(module.performanceTests.isEmpty, "\(module.id): ohne Test bleiben die Zonen geschätzt")
            for test in module.performanceTests {
                XCTAssertTrue(Set(test.produces).isSubset(of: metrics), "\(module.id) \(test.id)")
                XCTAssertGreaterThan(test.durationMinutes, 0, "\(module.id) \(test.id)")
            }
            for scheme in module.zoneSchemes {
                XCTAssertTrue(module.targets.contains(scheme.target), "\(module.id) \(scheme.target)")
                XCTAssertTrue(metrics.contains(scheme.basis) || athlete.contains(scheme.basis), "\(module.id) \(scheme.basis)")
            }
        }
    }

    func testEveryZoneSchemeGivesAscendingAdjoiningZonesForAPlausibleBasis() throws {
        let registry = try SportRegistry(modules: allModules)
        for module in allModules {
            for scheme in module.zoneSchemes {
                let definition = try XCTUnwrap(
                    registry.metricDefinition(scheme.basis, sport: module.id) ?? registry.metricDefinition(scheme.basis, sport: nil),
                    "\(module.id) \(scheme.basis)"
                )
                let middle = (definition.plausibleRange.lowerBound + definition.plausibleRange.upperBound) / 2
                let zones = scheme.zones(basisValue: middle).zones
                XCTAssertEqual(zones.map(\.zone), Array(1...(scheme.bounds.count + 1)), "\(module.id) \(scheme.target)")
                for (lower, upper) in zip(zones, zones.dropFirst()) {
                    switch scheme.scale {
                    case .proportional:
                        XCTAssertEqual(lower.maximum, upper.minimum, "\(module.id) \(scheme.target) Zone \(lower.zone)")
                    case .inversePace:
                        // Pace: Die höhere Zone ist schneller, also kürzer.
                        XCTAssertEqual(lower.minimum, upper.maximum, "\(module.id) \(scheme.target) Zone \(lower.zone)")
                    }
                }
            }
        }
    }

    func testEveryModuleEstimatesOnlyItsOwnPlausibleValues() throws {
        let registry = try SportRegistry(modules: allModules)
        let known = ResolvedPerformance(
            profile: .empty,
            estimates: [
                PerformanceValue(metric: .maxHeartRate, value: 188, source: .estimated, measuredAt: Date()),
                PerformanceValue(metric: .restingHeartRate, value: 52, source: .estimated, measuredAt: Date())
            ],
            registry: registry
        )
        for module in allModules {
            // Typische Einheiten: 45 Minuten im mittleren Zieltempo der Sportart.
            let speed = (module.goalSpeedRange.lowerBound + module.goalSpeedRange.upperBound) / 2
            let workouts = (1...4).map { day in
                TestFixtures.workout(module.id, daysAgo: day, minutes: 45, meters: speed * 45 * 60, heartRate: 140)
            }
            let context = PerformanceEstimationContext(sport: module.id, now: TestFixtures.now, workouts: workouts, known: known)
            for estimate in module.estimatePerformance(context) {
                let definition = try XCTUnwrap(registry.metricDefinition(estimate.metric, sport: module.id), "\(module.id) \(estimate.metric)")
                XCTAssertTrue(definition.plausibleRange.contains(estimate.value), "\(module.id) \(estimate.metric) \(estimate.value)")
                XCTAssertFalse(estimate.source.isConfirmed, "\(module.id): Schätzungen sind nie bestätigt")
            }
            let empty = PerformanceEstimationContext(
                sport: module.id, now: TestFixtures.now, workouts: [], known: ResolvedPerformance(profile: .empty, estimates: [])
            )
            XCTAssertTrue(module.estimatePerformance(empty).isEmpty, "\(module.id): ohne Daten nichts raten")
        }
    }

    func testTestSportHasItsOwnProfile() {
        // Eigener Wert, eigener Test, andere Zahl an Zonen: Das Profil hängt an keiner der echten Sportarten.
        let rowing = RowingTestModule()
        XCTAssertTrue(rowing.performanceTests.contains { $0.produces.contains(RowingTestModule.twoKilometerTime) })
        XCTAssertFalse(otherRealModules.contains { module in
            module.performanceMetrics.contains { $0.metric == RowingTestModule.twoKilometerTime }
        })
        XCTAssertEqual(rowing.zoneSchemes.first?.zones(basisValue: 160).zones.count, 4)
    }

    func testTestSportReallyHasItsOwnLogic() {
        // Rudern plant nach Schlagzahl, was keine der echten Sportarten kann: Der Test beweist nur dann etwas,
        // wenn die Test-Sportart nicht bloß eine Kopie einer echten ist.
        XCTAssertTrue(RowingTestModule().targets.contains(.strokeRate))
        XCTAssertFalse(otherRealModules.contains { $0.targets.contains(.strokeRate) })
    }

    func testEveryModuleHasStatisticsFromItsOwnWorkouts() {
        for module in allModules {
            XCTAssertTrue(SportStatistics.isValid(module.statistics), "\(module.id)")
            XCTAssertGreaterThanOrEqual(module.statistics.count, 2, "\(module.id): zwei Standard-Kacheln")
            XCTAssertTrue(module.statistics.contains { $0.metric == .duration }, "\(module.id): Stunden je Sportart brauchen die Zeit")
        }
    }
}
