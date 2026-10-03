import XCTest
@testable import SwimInstructorCore

/// Prüft die App gegen `contracts/`. Das Backend prüft dieselben Dateien (`backend/test/contracts.test.ts`):
/// So fällt ein Formatbruch zwischen App und Server in der CI auf, ohne Gerät und ohne laufenden Server.
final class ContractTests: XCTestCase {
    // MARK: - Sportarten

    private struct SportsContract: Decodable {
        struct Sport: Decodable {
            let id: String
            let displayName: String
            let measures: [String]
            let targets: [String]
            let goalSpeed: GoalSpeed
        }

        struct GoalSpeed: Decodable {
            let minMetersPerSecond: Double
            let maxMetersPerSecond: Double
        }

        let schemaVersion: Int
        let measures: [String]
        let targets: [String]
        let sports: [Sport]
    }

    private func sportsContract() throws -> SportsContract {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SportsContract.self, from: RepoPaths.contractData("sports.json"))
    }

    func testVocabularyMatchesContract() throws {
        let contract = try sportsContract()
        XCTAssertEqual(contract.schemaVersion, 1)
        XCTAssertEqual(contract.measures, StepMeasure.allCases.map(\.rawValue))
        XCTAssertEqual(contract.targets, StepTarget.allCases.map(\.rawValue))
    }

    func testRegisteredSportsMatchContract() throws {
        let contract = try sportsContract()
        XCTAssertEqual(contract.sports.map(\.id), SportRegistry.standard.ids.map(\.rawValue))
        for sport in contract.sports {
            let module = try XCTUnwrap(SportRegistry.standard.module(for: SportID(rawValue: sport.id)), sport.id)
            XCTAssertEqual(module.displayName, sport.displayName, sport.id)
            XCTAssertEqual(Set(module.measures.map(\.rawValue)), Set(sport.measures), sport.id)
            XCTAssertEqual(Set(module.targets.map(\.rawValue)), Set(sport.targets), sport.id)
            XCTAssertEqual(module.goalSpeedRange, sport.goalSpeed.minMetersPerSecond...sport.goalSpeed.maxMetersPerSecond, sport.id)
        }
    }

    // MARK: - Was über die Leitung geht

    func testSnapshotV1RoundTripsWithoutLosingFields() throws {
        let data = try RepoPaths.contractData("wire/snapshot-v1.json")
        let snapshot = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: data)
        let reencoded = try AthleteStateSnapshot.jsonEncoder().encode(snapshot)

        XCTAssertEqual(try JSONKeyPaths.of(reencoded), try JSONKeyPaths.of(data), "Die App schickt andere Felder als der Vertrag")
        XCTAssertEqual(try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: reencoded), snapshot)
        XCTAssertEqual(snapshot.schemaVersion, AthleteStateSnapshot.currentSchemaVersion)
    }

    func testSnapshotV2RoundTripsWithoutLosingFields() throws {
        let data = try RepoPaths.contractData("wire/snapshot-v2.json")
        let snapshot = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: data)
        let reencoded = try AthleteStateSnapshot.jsonEncoder().encode(snapshot)

        XCTAssertEqual(try JSONKeyPaths.of(reencoded), try JSONKeyPaths.of(data))
        XCTAssertEqual(try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: reencoded), snapshot)
        XCTAssertEqual(snapshot.schemaVersion, AthleteStateSnapshot.multiSportSchemaVersion)
        XCTAssertEqual(snapshot.sports?.map(\.sport), [.swim, .bike, .run])
        // v1-Teil für einen älteren Server: genau die Felder von snapshot-v1.json.
        let version1 = try AthleteStateSnapshot.jsonEncoder().encode(snapshot.version1)
        XCTAssertEqual(try JSONKeyPaths.of(version1), try JSONKeyPaths.of(RepoPaths.contractData("wire/snapshot-v1.json")))
    }

    func testAppBuildsTheV2PartsWithExactlyTheContractFields() throws {
        let now = TestFixtures.now
        let goal = try JSONDecoder().decode(TrainingGoal.self, from: RepoPaths.contractData("app-storage/training-goal.json"))
        func workout(_ sport: SportID, daysAgo: Int, minutes: Double, meters: Double) -> Workout {
            let start = TestFixtures.date(daysAgo: daysAgo, hour: 8)
            return Workout(id: UUID(), sport: sport, startDate: start, endDate: start.addingTimeInterval(minutes * 60), duration: minutes * 60, distanceMeters: meters)
        }
        let workouts = [
            workout(.swim, daysAgo: 1, minutes: 40, meters: 2000),
            workout(.bike, daysAgo: 3, minutes: 90, meters: 42_000),
            workout(.bike, daysAgo: 10, minutes: 80, meters: 36_000)
        ]
        let v1 = AthleteStateCalculator(calendar: TestFixtures.utc)
            .snapshot(workouts: workouts.compactMap(SwimWorkout.init(workout:)), goal: goal.legacySwimGoal, now: now)
        let v2 = MultiSportStateCalculator(calendar: TestFixtures.utc).extend(v1, workouts: workouts, goal: goal, now: now)

        let isV2Part = { (path: String) in ["training_goal", "sports", "total_load"].contains { path.hasPrefix($0) } }
        let built = try JSONKeyPaths.of(AthleteStateSnapshot.jsonEncoder().encode(v2)).filter(isV2Part)
        let contract = try JSONKeyPaths.of(RepoPaths.contractData("wire/snapshot-v2.json")).filter(isV2Part)
        XCTAssertEqual(built, contract)
    }

    func testTodayResponsesDecode() throws {
        let decoder = PlanResponse.jsonDecoder()
        let today = try decoder.decode(PlanResponse.self, from: RepoPaths.contractData("wire/plan-today-response.json"))
        XCTAssertEqual(today.source, .claude)
        XCTAssertEqual(today.plan.totalDistanceMeters, today.plan.sets.reduce(0) { $0 + $1.totalMeters })
        XCTAssertEqual(today.plan.equipmentNeeded, ["pull_buoy"])
        XCTAssertEqual(today.plan.sets.first?.cue, "Locker kraulen")
        XCTAssertEqual(today.wishes, "mehr Technik")

        let fallback = try decoder.decode(PlanResponse.self, from: RepoPaths.contractData("wire/plan-today-fallback-response.json"))
        XCTAssertEqual(fallback.source, .fallback)
        XCTAssertTrue(fallback.stale)
        XCTAssertEqual(fallback.fallbackReason, "timeout")
        XCTAssertTrue(fallback.plan.isRestDay)
    }

    func testWeekResponseDecodes() throws {
        let response = try PlanResponse.jsonDecoder().decode(WeekPlanResponse.self, from: RepoPaths.contractData("wire/plan-week-response.json"))
        XCTAssertEqual(response.weekPlan.weekStart, "2026-09-28")
        XCTAssertEqual(response.weekPlan.days.map(\.date), ["2026-09-30", "2026-10-01", "2026-10-02"])
        XCTAssertEqual(response.weekPlan.plannedMeters, response.plan.totalDistanceMeters)
    }

    func testMacroResponseDecodes() throws {
        let response = try PlanResponse.jsonDecoder().decode(MacroPlanResponse.self, from: RepoPaths.contractData("wire/plan-macro-response.json"))
        let plan = response.macroPlan(goalKey: "3800-3600-2027-07-04")
        XCTAssertEqual(plan.goalDay, "2027-07-04")
        XCTAssertEqual(plan.weeks.map(\.phase), [.base, .base, .base, .taper, .goalWeek])
        XCTAssertEqual(plan.peakMeters, 3800)
    }

    // MARK: - Was die App heute auf dem Gerät speichert

    func testStoredLastPlanFromBeforeEquipmentStillLoads() throws {
        let plan = try XCTUnwrap(FilePlanCache(fileURL: RepoPaths.contract("app-storage/last-plan.json")).load())
        XCTAssertEqual(plan.plan.sets.count, 1)
        XCTAssertEqual(plan.plan.sets.first?.equipment, [])
        XCTAssertEqual(plan.plan.sets.first?.cue, "")
        XCTAssertNil(plan.wishes)
    }

    func testStoredPlanHistoryLoads() {
        let history = FilePlanHistory(fileURL: RepoPaths.contract("app-storage/plan-history.json")).load()
        XCTAssertEqual(history.map(\.date), ["2026-09-28", "2026-09-29"])
        XCTAssertEqual(history.last?.plan.equipmentNeeded, ["pull_buoy", "paddles"])
    }

    func testStoredWeekPlansIncludingOldFormLoad() {
        let weeks = FileWeekPlanStore(fileURL: RepoPaths.contract("app-storage/week-plans.json")).load()
        XCTAssertEqual(weeks.map(\.weekStart), ["2026-09-28", "2026-10-05"])
        // Alte Form ohne Markierungen des Athleten.
        XCTAssertEqual(weeks.first?.days.map(\.isUnavailable), [false, false])
        // Neue Form mit "keine Zeit" und gemerktem Inhalt.
        let blocked = weeks.last?.day(on: "2026-10-06")
        XCTAssertEqual(blocked?.isUnavailable, true)
        XCTAssertEqual(blocked?.contentBeforeUnavailable?.targetDistanceMeters, 1000)
        XCTAssertEqual(weeks.last?.day(on: "2026-10-07")?.isEdited, true)
    }

    func testStoredSwimGoalFromBeforeT2BecomesTheTrainingGoal() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ContractTests-\(UUID().uuidString)"))
        defaults.set(try RepoPaths.contractData("app-storage/goal-swim-v1.json"), forKey: UserDefaultsGoalStore.storageKey)

        let goal = UserDefaultsTrainingGoalStore(defaults: defaults).goal()

        XCTAssertEqual(goal.disciplines, [.init(sport: .swim, distanceMeters: 2000, targetDurationSeconds: 2700)])
        XCTAssertEqual(goal.emphasis, [.init(sport: .swim, percent: 100)])
        XCTAssertEqual(goal.targetDate, Date(timeIntervalSinceReferenceDate: 836_388_000))
        XCTAssertEqual(goal.legacySwimGoal, try JSONDecoder().decode(AthleteGoal.self, from: RepoPaths.contractData("app-storage/goal-swim-v1.json")))
    }

    func testStoredTrainingGoalLoads() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ContractTests-\(UUID().uuidString)"))
        defaults.set(try RepoPaths.contractData("app-storage/training-goal.json"), forKey: UserDefaultsTrainingGoalStore.storageKey)

        let goal = UserDefaultsTrainingGoalStore(defaults: defaults).goal()

        XCTAssertEqual(goal.template, "triathlon_olympic")
        XCTAssertEqual(goal.disciplines.map(\.sport), [.swim, .bike, .run])
        XCTAssertNil(goal.disciplines.last?.targetDurationSeconds)
        XCTAssertEqual(goal.percent(for: .bike), 35)
    }

    func testStoredMacroPlanLoads() throws {
        let plan = try XCTUnwrap(FileMacroPlanStore(fileURL: RepoPaths.contract("app-storage/macro-plan.json")).load())
        XCTAssertEqual(plan.goalKey, "3800-3600-2027-07-04")
        XCTAssertEqual(plan.weeks.count, 3)
        XCTAssertEqual(plan.weeks.last?.phase, .goalWeek)
    }
}
