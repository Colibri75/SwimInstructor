import XCTest
@testable import SwimInstructorCore

final class TrainingGoalStoreTests: XCTestCase {
    private let now = TestFixtures.now

    private func makeDefaults() -> UserDefaults {
        let suite = "TrainingGoalStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func olympic(daysAhead: Double = 200) -> TrainingGoal {
        GoalTemplate.template(id: "triathlon_olympic")!
            .goal(targetDate: now.addingTimeInterval(daysAhead * 86_400), trainingDaysPerWeek: 5, weeklyHours: 8)
            .settingEmphasis(40, for: .swim)
    }

    func testWithoutAnythingStoredTheDefaultGoalApplies() {
        XCTAssertEqual(UserDefaultsTrainingGoalStore(defaults: makeDefaults()).goal(), .default)
    }

    func testTheSwimGoalFromBeforeT2Moves() {
        let defaults = makeDefaults()
        let old = AthleteGoal(distanceMeters: 1500, targetDurationSeconds: 1800, targetDate: now.addingTimeInterval(100 * 86_400))
        XCTAssertTrue(UserDefaultsGoalStore(defaults: defaults).setGoal(old))

        let goal = UserDefaultsTrainingGoalStore(defaults: defaults).goal()

        XCTAssertEqual(goal, TrainingGoal(legacy: old))
        XCTAssertEqual(goal.legacySwimGoal, old)
    }

    func testASavedGoalSurvivesARestartAndWinsOverTheOldOne() {
        let defaults = makeDefaults()
        UserDefaultsGoalStore(defaults: defaults).setGoal(AthleteGoal(distanceMeters: 1500, targetDurationSeconds: 1800, targetDate: now))
        let store = UserDefaultsTrainingGoalStore(defaults: defaults, calendar: TestFixtures.utc)

        XCTAssertTrue(store.setGoal(olympic(), now: now))

        XCTAssertEqual(UserDefaultsTrainingGoalStore(defaults: defaults).goal(), olympic())
        XCTAssertEqual(UserDefaultsTrainingGoalStore(defaults: defaults).goal().percent(for: .swim), 40)
    }

    func testInvalidGoalsAreNotSaved() {
        let store = UserDefaultsTrainingGoalStore(defaults: makeDefaults(), calendar: TestFixtures.utc)
        XCTAssertTrue(store.setGoal(olympic(), now: now))

        var wrongSum = olympic()
        wrongSum.emphasis[0].percent = 90
        XCTAssertFalse(store.setGoal(wrongSum, now: now))
        XCTAssertFalse(store.setGoal(olympic(daysAhead: -3), now: now), "Zieltag in der Vergangenheit")

        XCTAssertEqual(store.goal(), olympic())
    }

    func testBrokenStoredDataFallsBack() {
        let defaults = makeDefaults()
        defaults.set(Data("kaputt".utf8), forKey: UserDefaultsTrainingGoalStore.storageKey)
        XCTAssertEqual(UserDefaultsTrainingGoalStore(defaults: defaults).goal(), .default)

        // Gespeichert, aber ungültig (etwa eine Sportart, die es nicht mehr gibt): ebenfalls das Standardziel.
        var unknown = olympic()
        unknown.disciplines[0].sport = "kayak"
        defaults.set(try? JSONEncoder().encode(unknown), forKey: UserDefaultsTrainingGoalStore.storageKey)
        XCTAssertEqual(UserDefaultsTrainingGoalStore(defaults: defaults).goal(), .default)
    }

    func testResetRemovesNewAndOldGoal() {
        let defaults = makeDefaults()
        UserDefaultsGoalStore(defaults: defaults).setGoal(AthleteGoal(distanceMeters: 1500, targetDurationSeconds: 1800, targetDate: now))
        let store = UserDefaultsTrainingGoalStore(defaults: defaults, calendar: TestFixtures.utc)
        store.setGoal(olympic(), now: now)

        store.resetGoal()

        XCTAssertEqual(store.goal(), .default)
    }
}
