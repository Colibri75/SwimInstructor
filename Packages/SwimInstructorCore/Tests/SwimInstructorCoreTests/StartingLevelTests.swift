import XCTest
@testable import SwimInstructorCore

final class StartingLevelTests: XCTestCase {
    private let now = TestFixtures.now

    private func makeStore() -> UserDefaultsStartingLevelStore {
        let suite = "StartingLevelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStartingLevelStore(defaults: defaults)
    }

    private func level(_ sport: SportID, _ weekly: Double, _ longest: Double, daysAgo: Double = 0) -> StartingLevel {
        StartingLevel(sport: sport, weeklyAmount: weekly, longestSession: longest, status: .shortBreak,
                      reportedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    func testStoreKeepsOneLevelPerSportInRegistryOrder() {
        let store = makeStore()
        XCTAssertEqual(store.levels(), [])

        XCTAssertTrue(store.setLevel(level(.run, 180, 90)))
        XCTAssertTrue(store.setLevel(level(.swim, 6000, 2500)))
        XCTAssertTrue(store.setLevel(level(.swim, 7000, 3000)))

        XCTAssertEqual(store.levels().map(\.sport), [.swim, .run])
        XCTAssertEqual(store.levels().first?.weeklyAmount, 7000)

        store.removeLevel(for: .swim)
        XCTAssertEqual(store.levels().map(\.sport), [.run])
    }

    func testStoreRejectsAmountsOutsideTheRangeOfTheSport() {
        let store = makeStore()
        // Laufen plant in Minuten: 6000 sind dort über der Grenze, Schwimmen in Metern nicht.
        XCTAssertFalse(store.setLevel(level(.run, 6000, 90)))
        XCTAssertFalse(store.setLevel(level(.swim, 6000, -1)))
        XCTAssertFalse(store.setLevel(level(SportID(rawValue: "kayak"), 100, 50)))
        XCTAssertEqual(store.levels(), [])
    }

    func testALevelIsValidFor28Days() {
        XCTAssertTrue(level(.swim, 6000, 2500, daysAgo: 27).isValid(now: now))
        XCTAssertTrue(level(.swim, 6000, 2500, daysAgo: 28).isValid(now: now))
        XCTAssertFalse(level(.swim, 6000, 2500, daysAgo: 29).isValid(now: now))
        XCTAssertFalse(level(.swim, 6000, 2500, daysAgo: -3).isValid(now: now), "aus der Zukunft gilt nicht")
    }

    func testSummaryCountsValidLevels() {
        XCTAssertEqual(StartingLevelFormatting.summary([], now: now), "Nicht angegeben")
        XCTAssertEqual(StartingLevelFormatting.summary([level(.swim, 6000, 2500, daysAgo: 40)], now: now), "Abgelaufen")
        XCTAssertEqual(StartingLevelFormatting.summary([level(.swim, 6000, 2500)], now: now), "1 Sportart")
        XCTAssertEqual(StartingLevelFormatting.summary([level(.swim, 6000, 2500), level(.run, 180, 90)], now: now), "2 Sportarten")
    }

    func testSuggestionRoundsHealthValuesToTheStep() throws {
        let snapshot = try AthleteStateSnapshot.jsonDecoder().decode(
            AthleteStateSnapshot.self, from: RepoPaths.contractData("wire/snapshot-v2.json")
        )
        let swim = try XCTUnwrap(snapshot.sports?.first { $0.sport == .swim })

        let suggestion = StartingLevelFormatting.suggestion(sport: .swim, state: swim, unit: .meters, now: now)

        XCTAssertEqual(suggestion.weeklyAmount, (swim.averageWeeklyMeters / 100).rounded() * 100)
        XCTAssertEqual(suggestion.longestSession, (swim.longestSessionMeters / 100).rounded() * 100)
        XCTAssertEqual(suggestion.status, .regular)
        XCTAssertEqual(suggestion.reportedAt, now)
        XCTAssertEqual(StartingLevelFormatting.suggestion(sport: .run, state: nil, unit: .minutes, now: now).weeklyAmount, 0)
    }

    func testOnlyValidLevelsOfSnapshotSportsGoIntoTheSnapshot() async throws {
        let goal = GoalTemplate.template(id: "triathlon_olympic")!
            .goal(targetDate: AthleteGoal.default.targetDate, trainingDaysPerWeek: 5, weeklyHours: 7)
        let levels = [level(.swim, 6000, 2500, daysAgo: 2), level(.run, 180, 90, daysAgo: 40)]
        let builder = SnapshotBuilder(
            repository: FakeAllSportsRepository(workouts: []),
            vitalsRepository: FakeVitalsRepository(),
            trainingGoalProvider: { goal },
            startingLevelsProvider: { levels },
            calendar: TestFixtures.utc
        )

        let snapshot = try await builder.build(now: now).snapshot

        XCTAssertEqual(snapshot.startingLevels, [levels[0]])
        XCTAssertNil(snapshot.version1.startingLevels)
    }
}
