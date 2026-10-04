import XCTest
@testable import SwimInstructorCore

final class OnboardingStoreTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "OnboardingStoreTests-\(UUID().uuidString)"))
    }

    func testNewInstallNeedsTheSetupUntilCompleted() throws {
        let defaults = try defaults()
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        XCTAssertFalse(store.isCompleted)

        // Ein Ziel, das während der Einrichtung gespeichert wird, überspringt sie nicht.
        let goal = GoalTemplate.template(id: "run_marathon")!
            .goal(targetDate: Date().addingTimeInterval(120 * 86_400), trainingDaysPerWeek: 4, weeklyHours: 5)
        XCTAssertTrue(UserDefaultsTrainingGoalStore(defaults: defaults).setGoal(goal, now: Date()))
        XCTAssertFalse(store.isCompleted)

        store.complete()
        XCTAssertTrue(store.isCompleted)
        XCTAssertTrue(UserDefaultsOnboardingStore(defaults: defaults).isCompleted)
    }

    func testExistingUsersSeeTheSetupOnceWithTheirGoal() throws {
        let defaults = try defaults()
        defaults.set(try RepoPaths.contractData("app-storage/training-goal.json"), forKey: UserDefaultsTrainingGoalStore.storageKey)
        let store = UserDefaultsOnboardingStore(defaults: defaults)
        XCTAssertFalse(store.isCompleted)
        // Vorausgefüllt: Der Assistent liest das gespeicherte Ziel.
        XCTAssertEqual(UserDefaultsTrainingGoalStore(defaults: defaults).goal().template, "triathlon_olympic")
        store.complete()
        XCTAssertTrue(store.isCompleted)
    }
}
