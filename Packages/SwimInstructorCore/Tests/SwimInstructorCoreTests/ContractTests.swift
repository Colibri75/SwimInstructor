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

    func testStoredMacroPlanLoads() throws {
        let plan = try XCTUnwrap(FileMacroPlanStore(fileURL: RepoPaths.contract("app-storage/macro-plan.json")).load())
        XCTAssertEqual(plan.goalKey, "3800-3600-2027-07-04")
        XCTAssertEqual(plan.weeks.count, 3)
        XCTAssertEqual(plan.weeks.last?.phase, .goalWeek)
    }
}
