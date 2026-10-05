import XCTest
import HealthKit
@testable import SwimInstructorCore

/// Kataloge der Module, die gespeicherte Anordnung der Kacheln und das Bearbeiten auf dem Dashboard.
final class StatisticLayoutTests: XCTestCase {
    private final class MemoryStore: StatisticLayoutStoring {
        var stored: StatisticLayout?
        var saves = 0

        func load() -> StatisticLayout? { stored }

        func save(_ layout: StatisticLayout) throws {
            stored = layout
            saves += 1
        }
    }

    private static let withRowing = StatisticData.registry
    /// Nur die drei Triathlon-Sportarten: Die erwarteten Kacheln bleiben gleich, wenn die App weitere Sportarten bekommt.
    private static let triathlon = TestFixtures.triathlon

    /// "Sportart/Kennzahl/Zeitraum", `all` für alle Sportarten.
    private func describe(_ tiles: [StatisticTile]) -> [String] {
        tiles.map { "\($0.sport?.rawValue ?? "all")/\($0.metric.rawValue)/\($0.period.rawValue)" }
    }

    // MARK: - Kataloge

    func testTheThreeSportsBringTheirOwnCatalog() {
        let registry = SportRegistry.standard

        XCTAssertEqual(registry.statistics(for: "swim").map(\.metric.rawValue), [
            "distance", "pace_per_100m", "duration", "sessions", "average_heart_rate", "strokes_per_100m", "longest_distance", "training_load"
        ])
        XCTAssertEqual(registry.statistics(for: "bike").map(\.metric.rawValue), [
            "distance", "speed", "duration", "sessions", "average_heart_rate", "average_power", "average_cadence", "elevation_gain",
            "longest_distance", "training_load"
        ])
        XCTAssertEqual(registry.statistics(for: "run").map(\.metric.rawValue), [
            "distance", "pace_per_km", "duration", "sessions", "average_heart_rate", "average_power", "elevation_gain",
            "longest_distance", "training_load"
        ])
        XCTAssertEqual(registry.statistics(for: "swim").first?.unit, "m")
        XCTAssertEqual(registry.statistics(for: "run").first?.unit, "km")
        XCTAssertEqual(registry.statistics(for: nil).map(\.metric.rawValue), [
            "duration", "training_load", "sessions", "plan_adherence", "resting_heart_rate", "heart_rate_variability", "sleep"
        ])
        XCTAssertEqual(registry.statistics(for: "kayak"), [], "Unbekannte Sportart")
    }

    func testRowingGetsACatalogWithoutListingOne() {
        XCTAssertEqual(Self.withRowing.statistics(for: "rowing").map(\.metric.rawValue), [
            "duration", "sessions", "average_heart_rate", "average_power", "longest_duration", "training_load"
        ])
    }

    func testDerivedCatalogFollowsTheHealthMapping() {
        let meters = SportStatistics.derived(for: MeterStubModule())
        XCTAssertEqual(meters.map(\.metric.rawValue), [
            "distance", "duration", "sessions", "speed", "average_heart_rate", "elevation_gain", "longest_distance", "training_load"
        ])
        XCTAssertEqual(meters.filter { $0.metric == .distance || $0.metric == .longestDistance }.map(\.unit), ["m", "m"])

        let bike = SportStatistics.derived(for: BikeModule())
        XCTAssertEqual(bike.map(\.metric.rawValue), [
            "distance", "duration", "sessions", "speed", "average_heart_rate", "average_cadence", "average_power", "longest_distance",
            "training_load"
        ])
        XCTAssertEqual(bike.first?.unit, "km")
        XCTAssertNil(StatisticDefinition.forWorkoutMetric(.laps))
    }

    func testRegistryRejectsBrokenCatalogs() throws {
        let sleepForASport = StatisticDefinition.sleep
        let broken: [[StatisticDefinition]] = [
            [],
            [.duration, .duration],
            [StatisticDefinition(metric: "Pace/km", displayName: "Pace", unit: "/km", measure: .pace(meters: 1000), format: .pace)],
            [StatisticDefinition(metric: "pace", displayName: "  ", unit: "/km", measure: .pace(meters: 1000), format: .pace)],
            [.duration, sleepForASport]
        ]
        for statistics in broken {
            XCTAssertThrowsError(try SportRegistry(modules: [CatalogStubModule(statistics: statistics)])) { error in
                XCTAssertEqual(error as? SportRegistry.Problem, .invalidStatistics("kayak"), "\(statistics.map(\.metric))")
            }
        }
        XCTAssertNoThrow(try SportRegistry(modules: [CatalogStubModule(statistics: [.duration, .sessions])]))
    }

    // MARK: - Standard

    func testStandardLayout() {
        let layout = StatisticLayout.standard(registry: Self.triathlon)

        XCTAssertEqual(describe(layout.tiles), [
            "all/duration/week", "all/plan_adherence/4_weeks",
            "swim/distance/4_weeks", "swim/pace_per_100m/4_weeks",
            "bike/distance/4_weeks", "bike/speed/4_weeks",
            "run/distance/4_weeks", "run/pace_per_km/4_weeks",
            "all/training_load/7_days", "all/resting_heart_rate/4_weeks", "all/heart_rate_variability/4_weeks", "all/sleep/7_days"
        ])
        XCTAssertEqual(layout.knownSports, ["swim", "bike", "run"])
        XCTAssertEqual(layout.version, 1)
        XCTAssertEqual(Set(layout.tiles.map(\.id)).count, layout.tiles.count)
    }

    func testRowingGetsTilesAutomatically() {
        let layout = StatisticLayout.standard(registry: Self.withRowing)

        XCTAssertTrue(describe(layout.tiles).contains("rowing/duration/4_weeks"))
        XCTAssertTrue(describe(layout.tiles).contains("rowing/sessions/4_weeks"))
    }

    // MARK: - Gespeicherte Anordnung nach einem Update

    /// So hätte eine frühere Version gespeichert, mit Dingen, die es nicht mehr gibt, und Feldern einer neueren Version.
    private static let storedJSON = """
    {
      "version": 1,
      "knownSports": ["swim", "bike", "run"],
      "columns": 2,
      "tiles": [
        {"id": "6F1F5D2E-0000-4000-8000-000000000001", "sport": "run", "metric": "pace_per_km", "period": "4_weeks"},
        {"id": "6F1F5D2E-0000-4000-8000-000000000002", "metric": "duration", "period": "week"},
        {"id": "6F1F5D2E-0000-4000-8000-000000000003", "sport": "swim", "metric": "swolf", "period": "7_days"},
        {"id": "6F1F5D2E-0000-4000-8000-000000000004", "sport": "kayak", "metric": "distance", "period": "3_days", "color": "blue"},
        {"id": "6F1F5D2E-0000-4000-8000-000000000005", "sport": "bike"},
        {"id": "6F1F5D2E-0000-4000-8000-000000000001", "sport": "bike", "metric": "speed", "period": "7_days"}
      ]
    }
    """

    private func storedLayout() throws -> StatisticLayout {
        try JSONDecoder().decode(StatisticLayout.self, from: Data(Self.storedJSON.utf8))
    }

    func testStoredLayoutIsReadLeniently() throws {
        let layout = try storedLayout()

        // Die Kachel ohne Kennzahl fällt weg; ein unbekannter Zeitraum wird zum Standard.
        XCTAssertEqual(describe(layout.tiles), [
            "run/pace_per_km/4_weeks", "all/duration/week", "swim/swolf/7_days", "kayak/distance/4_weeks", "bike/speed/7_days"
        ])
        XCTAssertEqual(layout.tiles.first?.id, UUID(uuidString: "6F1F5D2E-0000-4000-8000-000000000001"))
    }

    func testRemovedMetricsAndSportsFallBackToAStandard() throws {
        let updated = try storedLayout().updated(for: Self.triathlon)

        XCTAssertEqual(describe(updated.tiles), [
            "run/pace_per_km/4_weeks",
            "all/duration/week",
            // Schwimmen hat kein SWOLF: die erste Kennzahl des Schwimmens.
            "swim/distance/7_days",
            // Kajak gibt es nicht: alle Sportarten; Umfang gibt es dort nicht: Stunden je Sportart.
            "all/duration/4_weeks"
        ], "Die doppelte Kennung zählt einmal")
        XCTAssertEqual(updated.knownSports, ["swim", "bike", "run"])
    }

    func testANewSportAddsItsTilesAtTheEnd() throws {
        let updated = try storedLayout().updated(for: Self.withRowing)

        XCTAssertEqual(describe(updated.tiles).suffix(2), ["rowing/duration/4_weeks", "rowing/sessions/4_weeks"])
        XCTAssertEqual(updated.knownSports, ["swim", "bike", "run", "rowing"])
        XCTAssertEqual(updated.updated(for: Self.withRowing), updated, "Nur einmal")
    }

    func testAnUnknownSportKeepsAMetricThatAllSportsHave() {
        let tile = StatisticTile(sport: "kayak", metric: .sessions, period: .sevenDays)

        let resolved = SportRegistry.standard.resolve(tile)

        XCTAssertNil(resolved.tile.sport)
        XCTAssertEqual(resolved.tile.metric, .sessions)
        XCTAssertEqual(resolved.tile.id, tile.id)
        XCTAssertEqual(resolved.definition, .sessions)
    }

    func testLayoutWithoutTilesListIsUnreadable() {
        XCTAssertThrowsError(try JSONDecoder().decode(StatisticLayout.self, from: Data(#"{"version": 1}"#.utf8)))
        let minimal = try? JSONDecoder().decode(StatisticLayout.self, from: Data(#"{"tiles": []}"#.utf8))
        XCTAssertEqual(minimal?.tiles, [])
        XCTAssertEqual(minimal?.knownSports, [])
        XCTAssertEqual(minimal?.version, 1)
    }

    // MARK: - Speicher

    func testUserDefaultsKeepTheLayoutAcrossLaunches() throws {
        let suite = "statistic-layout-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsStatisticLayoutStore(defaults: defaults)
        XCTAssertNil(store.load())

        let layout = try storedLayout().updated(for: .standard)
        try store.save(layout)

        XCTAssertEqual(UserDefaultsStatisticLayoutStore(defaults: defaults).load(), layout)

        defaults.set(Data("kaputt".utf8), forKey: UserDefaultsStatisticLayoutStore.storageKey)
        XCTAssertNil(store.load(), "Unlesbar: dann gilt der Standard")
    }

    // MARK: - Dashboard

    @MainActor
    func testDashboardStartsWithTheStandardAndSavesOnlyChanges() {
        let store = MemoryStore()
        let dashboard = StatisticDashboard(store: store, registry: Self.triathlon)

        XCTAssertEqual(describe(dashboard.tiles), describe(StatisticLayout.standard(registry: Self.triathlon).tiles))
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(dashboard.sports, [nil, "swim", "bike", "run"])
        XCTAssertEqual(dashboard.catalog(for: "run"), SportRegistry.standard.statistics(for: "run"))

        let first = dashboard.tiles[0]
        dashboard.setPeriod(first.period, for: first.id)
        XCTAssertEqual(store.saves, 0, "Nichts geändert")

        dashboard.setPeriod(.eightWeeks, for: first.id)
        XCTAssertEqual(dashboard.tiles[0].period, .eightWeeks)
        XCTAssertEqual(store.stored, dashboard.layout)
        XCTAssertEqual(store.saves, 1)
    }

    @MainActor
    func testChangingTheSportKeepsTheMetricIfThereIsOne() {
        let run = StatisticTile(sport: "run", metric: .pacePerKilometer, period: .fourWeeks)
        let time = StatisticTile(sport: "run", metric: .duration, period: .sevenDays)
        let store = MemoryStore()
        store.stored = StatisticLayout(tiles: [run, time], knownSports: ["swim", "bike", "run"])
        let dashboard = StatisticDashboard(store: store, registry: Self.triathlon)

        dashboard.setSport("bike", for: time.id)
        dashboard.setSport("bike", for: run.id)
        XCTAssertEqual(describe(dashboard.tiles), ["bike/distance/4_weeks", "bike/duration/7_days"])

        dashboard.setSport(nil, for: run.id)
        dashboard.setSport(nil, for: time.id)
        XCTAssertEqual(describe(dashboard.tiles), ["all/duration/4_weeks", "all/duration/7_days"])
        XCTAssertEqual(dashboard.tiles.map(\.id), [run.id, time.id])
    }

    @MainActor
    func testOnlyMetricsOfTheSportCanBeChosen() {
        let tile = StatisticTile(sport: "swim", metric: .distance, period: .fourWeeks)
        let store = MemoryStore()
        store.stored = StatisticLayout(tiles: [tile], knownSports: ["swim", "bike", "run"])
        let dashboard = StatisticDashboard(store: store, registry: Self.triathlon)

        dashboard.setMetric(.pacePerKilometer, for: tile.id)
        dashboard.setMetric(.pacePerKilometer, for: UUID())
        XCTAssertEqual(dashboard.tiles[0].metric, .distance)
        XCTAssertEqual(store.saves, 0)

        dashboard.setMetric(.pacePerHundredMeters, for: tile.id)
        XCTAssertEqual(dashboard.tiles[0].metric, .pacePerHundredMeters)
    }

    @MainActor
    func testAddRemoveAndReset() {
        let store = MemoryStore()
        let dashboard = StatisticDashboard(store: store, registry: Self.triathlon)
        let count = dashboard.tiles.count

        dashboard.add(sport: "bike", metric: .pacePerKilometer, period: .sevenDays)
        XCTAssertEqual(describe(dashboard.tiles).last, "bike/distance/7_days")

        let added = dashboard.tiles[count].id
        dashboard.remove(added)
        dashboard.remove(UUID())
        XCTAssertEqual(dashboard.tiles.count, count)

        dashboard.remove(dashboard.tiles[0].id)
        dashboard.reset()
        XCTAssertEqual(describe(dashboard.tiles), describe(StatisticLayout.standard(registry: Self.triathlon).tiles))
        XCTAssertEqual(store.saves, 4)
    }

    @MainActor
    func testSwipeToDeleteAndMoveInTheList() {
        let tiles = (0..<4).map { StatisticTile(sport: nil, metric: StatisticDefinition.overall[$0].metric, period: .fourWeeks) }
        let store = MemoryStore()
        store.stored = StatisticLayout(tiles: tiles, knownSports: ["swim", "bike", "run"])
        let dashboard = StatisticDashboard(store: store, registry: Self.triathlon)
        let ids = tiles.map(\.id)

        // Wie List.onMove: die erste ans Ende (Ziel 4), dann die letzte an den Anfang.
        dashboard.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        XCTAssertEqual(dashboard.tiles.map(\.id), [ids[1], ids[2], ids[3], ids[0]])
        dashboard.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        XCTAssertEqual(dashboard.tiles.map(\.id), ids)
        dashboard.move(fromOffsets: IndexSet([0, 1]), toOffset: 3)
        XCTAssertEqual(dashboard.tiles.map(\.id), [ids[2], ids[0], ids[1], ids[3]])
        dashboard.move(fromOffsets: IndexSet(integer: 9), toOffset: 0)

        dashboard.remove(atOffsets: IndexSet([0, 3]))
        XCTAssertEqual(dashboard.tiles.map(\.id), [ids[0], ids[1]])
        XCTAssertEqual(store.stored, dashboard.layout)
        XCTAssertEqual(store.saves, 4)
    }

    @MainActor
    func testDraggingATileOntoAnother() {
        let tiles = (0..<4).map { StatisticTile(sport: nil, metric: StatisticDefinition.overall[$0].metric, period: .fourWeeks) }
        let store = MemoryStore()
        store.stored = StatisticLayout(tiles: tiles, knownSports: ["swim", "bike", "run"])
        let dashboard = StatisticDashboard(store: store, registry: Self.triathlon)
        let ids = tiles.map(\.id)

        // Nach hinten gezogen: dahinter.
        dashboard.move(ids[0], to: ids[2])
        XCTAssertEqual(dashboard.tiles.map(\.id), [ids[1], ids[2], ids[0], ids[3]])

        // Nach vorn gezogen: davor.
        dashboard.move(ids[3], to: ids[1])
        XCTAssertEqual(dashboard.tiles.map(\.id), [ids[3], ids[1], ids[2], ids[0]])

        dashboard.move(ids[3], to: ids[3])
        dashboard.move(UUID(), to: ids[1])
        dashboard.move(ids[1], to: UUID())
        XCTAssertEqual(store.saves, 2)
    }

    @MainActor
    func testMovingOneStepForVoiceOver() {
        let tiles = (0..<3).map { StatisticTile(sport: nil, metric: StatisticDefinition.overall[$0].metric, period: .fourWeeks) }
        let store = MemoryStore()
        store.stored = StatisticLayout(tiles: tiles, knownSports: ["swim", "bike", "run"])
        let dashboard = StatisticDashboard(store: store, registry: Self.triathlon)
        let ids = tiles.map(\.id)

        dashboard.move(ids[0], by: 1)
        XCTAssertEqual(dashboard.tiles.map(\.id), [ids[1], ids[0], ids[2]])
        dashboard.move(ids[2], by: -1)
        XCTAssertEqual(dashboard.tiles.map(\.id), [ids[1], ids[2], ids[0]])

        dashboard.move(ids[1], by: -1)
        dashboard.move(ids[0], by: 1)
        dashboard.move(UUID(), by: 1)
        XCTAssertEqual(dashboard.tiles.map(\.id), [ids[1], ids[2], ids[0]])
    }

    @MainActor
    func testAStoredLayoutComesBackAfterARestart() {
        let store = MemoryStore()
        let first = StatisticDashboard(store: store, registry: Self.triathlon)
        let tile = first.tiles[2]
        first.setSport("run", for: tile.id)
        first.setMetric(.pacePerKilometer, for: tile.id)

        let restarted = StatisticDashboard(store: store, registry: Self.triathlon)

        XCTAssertEqual(restarted.tiles, first.tiles)
        XCTAssertEqual(restarted.tiles[2].sport, "run")
        XCTAssertEqual(restarted.tiles[2].metric, .pacePerKilometer)
    }
}

/// Eine Sportart mit Strecke in Metern ohne eigene Kennzahlen.
private struct MeterStubModule: SportModule {
    let id: SportID = "kayak"
    let displayName = "Kajak"
    let symbolName = "oar.2.crossed"
    let measures: Set<StepMeasure> = [.distance, .duration]
    let targets: Set<StepTarget> = [.perceivedEffort]
    let health = SportHealthMapping(
        activityTypes: [.paddleSports],
        distance: HealthQuantity(identifier: "HKQuantityTypeIdentifierDistancePaddleSports", unit: "m", aggregation: .sum),
        metrics: [
            .laps: HealthQuantity(identifier: "HKQuantityTypeIdentifierSwimmingStrokeCount", unit: "count", aggregation: .sum),
            .elevationGain: HealthQuantity(identifier: "HKQuantityTypeIdentifierFlightsClimbed", unit: "count", aggregation: .sum)
        ]
    )
    let loadFactor = 0.9
    let goalSpeedRange: ClosedRange<Double> = 0.5...6
    let planUnit = PlanUnit.meters
    let typicalSpeedMetersPerSecond = 2.0
}

/// Eine Sportart mit vorgegebenen Kennzahlen, für die Prüfung der Registry.
private struct CatalogStubModule: SportModule {
    let id: SportID = "kayak"
    let displayName = "Kajak"
    let symbolName = "oar.2.crossed"
    let measures: Set<StepMeasure> = [.duration]
    let targets: Set<StepTarget> = [.perceivedEffort]
    let health = SportHealthMapping(activityTypes: [.paddleSports], distance: nil)
    let loadFactor = 0.9
    let goalSpeedRange: ClosedRange<Double> = 0.5...6
    let planUnit = PlanUnit.minutes
    let typicalSpeedMetersPerSecond = 2.0
    let statistics: [StatisticDefinition]
}
