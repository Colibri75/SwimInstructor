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

    func testStoreKeepsPaceAndBestTimeOnlyWhenTheyFitTheSport() {
        let store = makeStore()
        var run = level(.run, 180, 90)
        run.pace = 330
        run.setBestTime(3000, over: 10_000)
        run.setBestTime(1450, over: 5000)
        XCTAssertTrue(store.setLevel(run))
        XCTAssertEqual(store.levels().first?.bestTime(over: 10_000), 3000)
        XCTAssertEqual(store.levels().first?.bestTimes?.map(\.distanceMeters), [5000, 10_000])
        XCTAssertEqual(store.levels().first?.pace, 330)

        var swim = level(.swim, 6000, 2500)
        swim.pace = 20
        XCTAssertFalse(store.setLevel(swim), "unter 1:00 pro 100 m")
        swim.pace = 125
        swim.setBestTime(3000, over: 10_000)
        XCTAssertFalse(store.setLevel(swim), "Schwimmen hat keine Bestzeit")
        run.setBestTime(600, over: 10_000)
        XCTAssertFalse(store.setLevel(run), "10 km in 10 Minuten")
        run.setBestTime(nil, over: 10_000)
        run.setBestTime(nil, over: 5000)
        XCTAssertNil(run.bestTimes)
        var bike = level(.bike, 180, 90)
        bike.pace = 27.5
        XCTAssertTrue(store.setLevel(bike))
    }

    func testOldStoredLevelsWithoutPaceStillLoad() throws {
        let suite = "StartingLevelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let old = #"[{"sport":"swim","weeklyAmount":6000,"longestSession":2500,"status":"regular","reportedAt":0}]"#
        defaults.set(Data(old.utf8), forKey: UserDefaultsStartingLevelStore.storageKey)
        let levels = UserDefaultsStartingLevelStore(defaults: defaults).levels()
        XCTAssertEqual(levels.count, 1)
        XCTAssertNil(levels.first?.pace)
        XCTAssertNil(levels.first?.bestTimes)
    }

    func testPaceAndClockTextsRoundTrip() throws {
        let swim = try XCTUnwrap(SwimModule().startingPace)
        let bike = try XCTUnwrap(BikeModule().startingPace)
        XCTAssertEqual(StartingLevelFormatting.paceText(125, pace: swim), "2:05")
        XCTAssertEqual(StartingLevelFormatting.parsePace("2:05", pace: swim), 125)
        XCTAssertEqual(StartingLevelFormatting.parsePace("27,5", pace: bike), 27.5)
        XCTAssertEqual(StartingLevelFormatting.parsePace("27.5", pace: bike), 27.5)
        XCTAssertNil(StartingLevelFormatting.parsePace("2:5", pace: swim))
        XCTAssertEqual(StartingLevelFormatting.paceUnit(swim), "/100 m")
        XCTAssertEqual(StartingLevelFormatting.paceUnit(bike), "km/h")
        XCTAssertEqual(StartingLevelFormatting.clockText(1500), "25:00")
        XCTAssertEqual(StartingLevelFormatting.clockText(3930), "1:05:30")
        XCTAssertEqual(StartingLevelFormatting.parseClock("1:05:30"), 3930)
        XCTAssertEqual(StartingLevelFormatting.parseClock("50:00"), 3000)
        XCTAssertNil(StartingLevelFormatting.parseClock("1:5:30"))
        XCTAssertEqual(StartingLevelFormatting.distanceText(10_000), "10 km")
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
