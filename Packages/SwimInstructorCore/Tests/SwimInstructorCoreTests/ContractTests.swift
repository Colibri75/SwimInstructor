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
            let loadFactor: Double
            let planUnit: String
            let typicalSpeedMetersPerSecond: Double
            let performanceMetrics: [Metric]
            let performanceTests: [Test]
        }

        struct GoalSpeed: Decodable {
            let minMetersPerSecond: Double
            let maxMetersPerSecond: Double
        }

        struct Metric: Decodable, Equatable {
            let id: String
            let displayName: String
            let unit: String
            let min: Double
            let max: Double

            init(id: String, displayName: String, unit: String, min: Double, max: Double) {
                self.id = id
                self.displayName = displayName
                self.unit = unit
                self.min = min
                self.max = max
            }

            init(_ definition: PerformanceMetricDefinition) {
                self.init(
                    id: definition.metric.rawValue, displayName: definition.displayName, unit: definition.unit,
                    min: definition.plausibleRange.lowerBound, max: definition.plausibleRange.upperBound
                )
            }
        }

        struct Test: Decodable, Equatable {
            let id: String
            let displayName: String
            let produces: [String]
            let maximalEffort: Bool
            let durationMinutes: Int

            init(id: String, displayName: String, produces: [String], maximalEffort: Bool, durationMinutes: Int) {
                self.id = id
                self.displayName = displayName
                self.produces = produces
                self.maximalEffort = maximalEffort
                self.durationMinutes = durationMinutes
            }

            init(_ test: PerformanceTest) {
                self.init(
                    id: test.id, displayName: test.displayName, produces: test.produces.map(\.rawValue),
                    maximalEffort: test.maximalEffort, durationMinutes: test.durationMinutes
                )
            }
        }

        let schemaVersion: Int
        let measures: [String]
        let targets: [String]
        let athleteMetrics: [Metric]
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
            XCTAssertEqual(module.loadFactor, sport.loadFactor, sport.id)
            XCTAssertEqual(module.planUnit.rawValue, sport.planUnit, sport.id)
            XCTAssertEqual(module.typicalSpeedMetersPerSecond, sport.typicalSpeedMetersPerSecond, sport.id)
            XCTAssertEqual(module.performanceMetrics.map { SportsContract.Metric($0) }, sport.performanceMetrics, sport.id)
            XCTAssertEqual(module.performanceTests.map { SportsContract.Test($0) }, sport.performanceTests, sport.id)
        }
    }

    func testAthleteMetricsMatchContract() throws {
        XCTAssertEqual(PerformanceMetricDefinition.athlete.map { SportsContract.Metric($0) }, try sportsContract().athleteMetrics)
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
        // Der Wochenraster mit Tageszeit und fester Sportart, damit alle seine Felder vorkommen.
        let schedule = try JSONDecoder().decode(WeeklySchedule.self, from: RepoPaths.contractData("app-storage/weekly-schedule.json"))
        let v2 = MultiSportStateCalculator(calendar: TestFixtures.utc).extend(v1, workouts: workouts, goal: goal, schedule: schedule, now: now)

        let isV2Part = { (path: String) in ["training_goal", "sports", "total_load"].contains { path.hasPrefix($0) } }
        let built = try JSONKeyPaths.of(AthleteStateSnapshot.jsonEncoder().encode(v2)).filter(isV2Part)
        let contract = try JSONKeyPaths.of(RepoPaths.contractData("wire/snapshot-v2.json")).filter(isV2Part)
        XCTAssertEqual(built, contract)
    }

    func testSnapshotV2WithProfileRoundTripsWithoutLosingFields() throws {
        let data = try RepoPaths.contractData("wire/snapshot-v2-profile.json")
        let snapshot = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: data)
        let reencoded = try AthleteStateSnapshot.jsonEncoder().encode(snapshot)

        XCTAssertEqual(try JSONKeyPaths.of(reencoded), try JSONKeyPaths.of(data))
        XCTAssertEqual(try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: reencoded), snapshot)
        XCTAssertEqual(snapshot.performance?.sports.map(\.sport), [.swim, .bike, .run])
        // Ohne Profil ist es genau der Snapshot v2 von vorher, für v1 genau der v1-Snapshot.
        let withoutProfile = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: RepoPaths.contractData("wire/snapshot-v2.json"))
        XCTAssertNil(withoutProfile.performance)
        XCTAssertEqual(snapshot.withMultiSport(trainingGoal: snapshot.trainingGoal!, sports: snapshot.sports!, totalLoad: snapshot.totalLoad!).performance, snapshot.performance)
        XCTAssertNil(snapshot.version1.performance)
    }

    func testAppBuildsExactlyTheContractProfile() throws {
        // Die Lage von snapshot-v2-profile.json: CSS getestet, Maximal- und Ruhepuls aus Health, zwei lockere Läufe.
        let profile = PerformanceProfile(values: [
            PerformanceValue(sport: .swim, metric: .criticalSwimPace, value: 105, source: .tested, measuredAt: ISO8601DateFormatter().date(from: "2026-09-20T08:00:00Z")!)
        ])
        let runs = [3, 6].map { TestFixtures.workout(.run, daysAgo: $0, minutes: 30, meters: 4944, heartRate: 142) }
        let input = PerformanceEstimationInput(
            now: TestFixtures.now,
            workouts: runs,
            vitals: [DailyVitals(date: TestFixtures.date(daysAgo: 0, hour: 0), restingHeartRate: 52)],
            observedMaximumHeartRate: 188,
            age: nil
        )
        let built = PerformanceEstimator().resolve(profile: profile, input: input).summary(sports: [.swim, .bike, .run])

        let contract = try AthleteStateSnapshot.jsonDecoder().decode(
            AthleteStateSnapshot.self, from: RepoPaths.contractData("wire/snapshot-v2-profile.json")
        )
        XCTAssertEqual(built, contract.performance)
    }

    func testSnapshotV2WithStartingLevelsRoundTripsWithoutLosingFields() throws {
        let data = try RepoPaths.contractData("wire/snapshot-v2-starting-levels.json")
        let snapshot = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: data)
        let reencoded = try AthleteStateSnapshot.jsonEncoder().encode(snapshot)

        XCTAssertEqual(try JSONKeyPaths.of(reencoded), try JSONKeyPaths.of(data))
        XCTAssertEqual(try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: reencoded), snapshot)
        // Wie die App sie anlegt: Schwimmen nach kurzer Pause, Laufen regelmäßig, zwei Tage vor dem Snapshot angegeben.
        let reportedAt = ISO8601DateFormatter().date(from: "2026-09-28T18:00:00Z")!
        XCTAssertEqual(snapshot.startingLevels, [
            StartingLevel(sport: .swim, weeklyAmount: 6000, longestSession: 2500, status: .shortBreak, reportedAt: reportedAt),
            StartingLevel(sport: .run, weeklyAmount: 180, longestSession: 90, status: .regular, reportedAt: reportedAt)
        ])
        // Ohne Startniveau ist es genau der Snapshot v2, für v1 genau der v1-Snapshot.
        let plain = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: RepoPaths.contractData("wire/snapshot-v2.json"))
        XCTAssertEqual(snapshot.withStartingLevels([]), plain)
        XCTAssertEqual(plain.withStartingLevels(snapshot.startingLevels!), snapshot)
        let version1 = try AthleteStateSnapshot.jsonEncoder().encode(snapshot.version1)
        XCTAssertEqual(try JSONKeyPaths.of(version1), try JSONKeyPaths.of(RepoPaths.contractData("wire/snapshot-v1.json")))
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

    func testStoredWeeklyScheduleLoads() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ContractTests-\(UUID().uuidString)"))
        defaults.set(try RepoPaths.contractData("app-storage/weekly-schedule.json"), forKey: UserDefaultsWeeklyScheduleStore.storageKey)

        let schedule = try XCTUnwrap(UserDefaultsWeeklyScheduleStore(defaults: defaults).storedSchedule())

        XCTAssertEqual(schedule.trainingDays, 5)
        XCTAssertEqual(schedule.totalMinutes, 450)
        XCTAssertEqual(schedule.day(2)?.sport, .swim)
        XCTAssertEqual(schedule.day(2)?.timeOfDay, .evening)
    }

    func testSnapshotV2CarriesTheWeeklyScheduleOfTheContract() throws {
        // snapshot-v2.json trägt denselben Wochenraster wie app-storage/weekly-schedule.json, Ziel daraus 5 Tage, 7,5 h.
        let snapshot = try AthleteStateSnapshot.jsonDecoder().decode(AthleteStateSnapshot.self, from: RepoPaths.contractData("wire/snapshot-v2.json"))
        let schedule = try JSONDecoder().decode(WeeklySchedule.self, from: RepoPaths.contractData("app-storage/weekly-schedule.json"))
        XCTAssertEqual(snapshot.trainingGoal?.weeklySchedule, schedule.days)
        XCTAssertEqual(snapshot.trainingGoal?.kind, .race)
        XCTAssertEqual(snapshot.trainingGoal?.trainingDaysPerWeek, schedule.trainingDays)
        XCTAssertEqual(snapshot.trainingGoal?.weeklyHours, Double(schedule.totalMinutes) / 60)
    }

    func testStoredPerformanceProfileLoads() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ContractTests-\(UUID().uuidString)"))
        defaults.set(try RepoPaths.contractData("app-storage/performance-profile.json"), forKey: UserDefaultsPerformanceProfileStore.storageKey)

        let profile = UserDefaultsPerformanceProfileStore(defaults: defaults).profile()

        XCTAssertEqual(profile.history(of: .criticalSwimPace, sport: .swim).map(\.value), [112, 105])
        XCTAssertEqual(profile.history(of: .thresholdHeartRate, sport: .run).first?.source, .manual)
        XCTAssertEqual(profile.history(of: .maxHeartRate).first?.value, 191)
        XCTAssertEqual(profile.values.count, 4)
    }

    func testStoredMacroPlanLoads() throws {
        let plan = try XCTUnwrap(FileMacroPlanStore(fileURL: RepoPaths.contract("app-storage/macro-plan.json")).load())
        XCTAssertEqual(plan.goalKey, "3800-3600-2027-07-04")
        XCTAssertEqual(plan.weeks.count, 3)
        XCTAssertEqual(plan.weeks.last?.phase, .goalWeek)
    }
}
