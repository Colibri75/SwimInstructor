import XCTest
@testable import SwimInstructorCore

/// Freiwasser: Ziel im Freiwasser, Zugang unter Equipment, Einheiten im Plan, Anzeige und Bearbeiten.
final class OpenWaterTests: XCTestCase {
    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try PlanCoding.jsonDecoder().decode(type, from: Data(json.utf8))
    }

    private static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: PlanCoding.jsonEncoder().encode(value)) as? [String: Any])
    }

    func testOnlySwimmingKnowsOpenWater() {
        XCTAssertEqual(SportRegistry.standard.module(for: .swim)?.openWater, OpenWaterVenue(id: "open_water", displayName: "Freiwasser", locationID: "open_water"))
        XCTAssertNil(SportRegistry.standard.module(for: .bike)?.openWater)
        XCTAssertEqual(SportRegistry.standard.venueIDs, ["indoor_trainer", "treadmill", "open_water"])
        // Die Watch kennt den Ort, den das Modul nennt.
        XCTAssertNotNil(SportRegistry.standard.module(for: .swim)?.recording.location(id: "open_water"))
    }

    func testTheAccessIsStoredWithTheIndoorEquipmentAndOffByDefault() {
        let suite = "OpenWaterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsIndoorEquipmentStore(defaults: defaults)

        XCTAssertEqual(store.ownedIndoorEquipment(), [])
        store.setOwnedIndoorEquipment(["open_water", "treadmill"])
        XCTAssertEqual(store.ownedIndoorEquipment(), ["treadmill", "open_water"])
    }

    func testTheGoalSendsOpenWaterOnlyWhenSet() throws {
        let lake = TrainingGoal.Discipline(sport: .swim, distanceMeters: 1_500, targetDurationSeconds: 1_800, openWater: true)
        let pool = TrainingGoal.Discipline(sport: .swim, distanceMeters: 1_500)

        XCTAssertEqual(try Self.object(lake)["open_water"] as? Bool, true)
        XCTAssertNil(try Self.object(pool)["open_water"])
        // Gespeicherte Ziele ohne das Feld bleiben lesbar.
        let old = try JSONDecoder().decode(TrainingGoal.Discipline.self, from: Data(#"{"sport":"swim","distanceMeters":1500}"#.utf8))
        XCTAssertFalse(old.openWater)
        let roundTrip = try JSONDecoder().decode(TrainingGoal.Discipline.self, from: JSONEncoder().encode(lake))
        XCTAssertEqual(roundTrip, lake)
    }

    func testOpenWaterIsOnlyValidForSportsThatKnowIt() {
        var goal = TrainingGoal(
            kind: .race,
            disciplines: [TrainingGoal.Discipline(sport: .swim, distanceMeters: 1_500, openWater: true), TrainingGoal.Discipline(sport: .run, distanceMeters: 10_000)],
            targetDate: Date(timeIntervalSince1970: 1_800_000_000),
            trainingDaysPerWeek: 5,
            weeklyHours: 8,
            emphasis: [TrainingGoal.Emphasis(sport: .swim, percent: 50), TrainingGoal.Emphasis(sport: .run, percent: 50)]
        )
        XCTAssertNil(goal.problem())

        goal.disciplines[1].openWater = true
        XCTAssertEqual(goal.problem(), "Laufen gibt es nicht im Freiwasser.")
    }

    func testSessionsCarryOpenWaterAndTheTargetOnlyWhenSet() throws {
        let day = try Self.decode(DaySession.self, #"{"sport":"swim","session_type":"endurance","intensity":"easy","focus":"See","test":null,"amount":1500,"unit":"meters","distance_meters":1500,"duration_minutes":35,"open_water":true,"steps":[]}"#)
        let week = try Self.decode(WeekSession.self, #"{"sport":"swim","session_type":"endurance","intensity":"easy","amount":1500,"unit":"meters","minutes":35,"distance_meters":1500,"focus":"See","test":null,"open_water":true}"#)
        let pool = WeekSession(sport: .swim, sessionType: .endurance, intensity: .easy, amount: 1_500, unit: .meters, minutes: 35, distanceMeters: 1_500, focus: "Becken")

        XCTAssertTrue(day.openWater)
        XCTAssertTrue(week.openWater)
        XCTAssertEqual(try Self.object(week.target)["open_water"] as? Bool, true)
        XCTAssertNil(try Self.object(pool.target)["open_water"])
    }

    func testChangingTheSportDropsOpenWater() throws {
        let swim = WeekSession(sport: .swim, sessionType: .endurance, intensity: .easy, amount: 1_500, unit: .meters, minutes: 35, distanceMeters: 1_500, focus: "See", openWater: true)
        let plan = WeekPlanV2(
            weekStart: "2026-09-28", generatedAt: Date(timeIntervalSince1970: 0), rationale: "r",
            days: [PlannedDay(date: "2026-09-30", content: PlannedDayContent(focus: "See", sessions: [swim]))]
        )

        let changed = MultiSportWeekEditor.changeSport(plan, date: "2026-09-30", session: 0, to: .run)

        XCTAssertEqual(changed.day(on: "2026-09-30")?.sessions.first?.sport, .run)
        XCTAssertEqual(changed.day(on: "2026-09-30")?.sessions.first?.openWater, false)
    }

    func testTheHintWarnsToNeverSwimAlone() {
        XCTAssertEqual(PlanV2Formatting.sessionHints(brick: false, indoor: false, openWater: true, sport: .swim, previous: nil), ["Freiwasser: nie allein, mit Boje"])
        XCTAssertEqual(PlanV2Formatting.sessionHints(brick: false, indoor: false, sport: .swim, previous: nil), [])
    }
}
