import XCTest
@testable import SwimInstructorCore

final class GoalStoreTests: XCTestCase {
    private func makeStore() -> (UserDefaultsGoalStore, UserDefaults) {
        let suite = "GoalStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (UserDefaultsGoalStore(defaults: defaults), defaults)
    }

    private func goal(meters: Double = 5000, minutes: Double = 100, year: Int = 2027, month: Int = 3, day: Int = 14) -> AthleteGoal {
        AthleteGoal(
            distanceMeters: meters,
            targetDurationSeconds: minutes * 60,
            targetDate: AthleteGoal.targetDate(onDayOf: TestFixtures.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!, calendar: TestFixtures.utc)
        )
    }

    func testWithoutAChoiceTheDefaultGoalApplies() {
        let (store, _) = makeStore()

        XCTAssertEqual(store.goal(), .default)
    }

    func testASavedGoalSurvivesAndCanBeChanged() {
        let (store, defaults) = makeStore()

        XCTAssertTrue(store.setGoal(goal()))
        // Neue Instanz auf denselben Defaults: wie nach einem Neustart der App.
        XCTAssertEqual(UserDefaultsGoalStore(defaults: defaults).goal(), goal())

        XCTAssertTrue(store.setGoal(goal(meters: 1500, minutes: 28)))
        XCTAssertEqual(store.goal().distanceMeters, 1500)
        XCTAssertEqual(store.goal().targetDurationSeconds, 28 * 60)
    }

    func testAnInvalidGoalIsNotSaved() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.setGoal(goal()))

        // 10 km in 10 Minuten: Zielpace 6 s pro 100 m.
        XCTAssertFalse(store.setGoal(goal(meters: 10_000, minutes: 10)))
        XCTAssertEqual(store.goal(), goal())
    }

    func testACorruptStoredValueFallsBackToTheDefault() {
        let (store, defaults) = makeStore()
        defaults.set(Data("kaputt".utf8), forKey: UserDefaultsGoalStore.storageKey)

        XCTAssertEqual(store.goal(), .default)
    }

    func testResetGoesBackToTheDefault() {
        let (store, _) = makeStore()
        store.setGoal(goal())

        store.resetGoal()

        XCTAssertEqual(store.goal(), .default)
    }

    func testGoalValidation() {
        XCTAssertNil(AthleteGoal.default.problem)
        XCTAssertNotNil(goal(meters: 50).problem)
        XCTAssertNotNil(goal(meters: 20_000).problem)
        XCTAssertNotNil(goal(minutes: 0).problem)
        XCTAssertNotNil(goal(minutes: 601).problem)
        // 400 m in 1 Minute: 15 s pro 100 m, zu schnell.
        XCTAssertNotNil(goal(meters: 400, minutes: 1).problem)
        // 100 m in 20 Minuten: 20 Minuten pro 100 m, zu langsam.
        XCTAssertNotNil(goal(meters: 100, minutes: 20).problem)
        XCTAssertNil(goal(meters: 1500, minutes: 28).problem)
    }

    func testTargetDateIsNoonInBerlinOnTheChosenDay() {
        let late = TestFixtures.utc.date(from: DateComponents(year: 2027, month: 7, day: 4, hour: 23, minute: 30))!

        let target = AthleteGoal.targetDate(onDayOf: late, calendar: TestFixtures.utc)

        XCTAssertEqual(target, AthleteGoal.default.targetDate)
    }

    func testSnapshotBuilderReadsTheGoalOnEveryRun() async throws {
        var current = goal()
        let builder = SnapshotBuilder(
            workoutRepository: FakeWorkoutRepository(workouts: []),
            vitalsRepository: FakeVitalsRepository(),
            goalProvider: { current },
            calendar: TestFixtures.utc
        )

        let first = try await builder.build(now: TestFixtures.now)
        current = goal(meters: 1500, minutes: 28)
        let second = try await builder.build(now: TestFixtures.now)

        XCTAssertEqual(first.snapshot.goal.distanceMeters, 5000)
        XCTAssertEqual(second.snapshot.goal.distanceMeters, 1500)
        XCTAssertEqual(second.snapshot.goal.targetDurationSeconds, 28 * 60)
    }
}
