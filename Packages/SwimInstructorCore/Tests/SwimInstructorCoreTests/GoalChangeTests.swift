import XCTest
@testable import SwimInstructorCore

final class GoalChangeTests: XCTestCase {
    private let now = TestFixtures.now
    private let calendar = TestFixtures.utc

    private func olympic(daysAhead: Int = 120) -> TrainingGoal {
        GoalTemplate.template(id: "triathlon_olympic")!
            .goal(targetDate: now.addingTimeInterval(TimeInterval(daysAhead * 86_400)), trainingDaysPerWeek: 5, weeklyHours: 7.5)
    }

    private func store() throws -> UserDefaultsTrainingGoalStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GoalChangeTests-\(UUID().uuidString)"))
        let store = UserDefaultsTrainingGoalStore(defaults: defaults, calendar: calendar)
        XCTAssertTrue(store.setGoal(olympic(), now: now))
        return store
    }

    // MARK: - Art der Änderung

    func testClassifiesChanges() {
        let goal = olympic()
        XCTAssertEqual(goal.change(to: goal, calendar: calendar), .none)

        var template = goal
        template.template = nil
        template.weeklyHours = 10
        XCTAssertEqual(goal.change(to: template, calendar: calendar), .none, "Vorlage und Stunden gehören nicht zum Plan")

        let fine: [TrainingGoal] = [
            goal.settingDiscipline(.init(sport: .run, distanceMeters: 10_000, targetDurationSeconds: 3000), for: .run),
            goal.settingEmphasis(40, for: .swim),
            { var shifted = goal; shifted.targetDate = goal.targetDate.addingTimeInterval(14 * 86_400); return shifted }()
        ]
        for changed in fine {
            XCTAssertEqual(goal.change(to: changed, calendar: calendar), .fineTuning)
        }

        let new: [TrainingGoal] = [
            goal.settingKind(.distance, now: now),
            goal.settingDiscipline(nil, for: .swim),
            goal.settingDiscipline(.init(sport: .run, distanceMeters: 21_100), for: .run),
            { var shifted = goal; shifted.targetDate = goal.targetDate.addingTimeInterval(15 * 86_400); return shifted }()
        ]
        for changed in new {
            XCTAssertEqual(goal.change(to: changed, calendar: calendar), .newGoal)
        }

        // Ein ungültiger Entwurf mit doppelter Sportart stürzt nicht ab.
        var broken = goal
        broken.disciplines.append(.init(sport: .run, distanceMeters: 5000))
        XCTAssertNotEqual(goal.change(to: broken, calendar: calendar), .none)
    }

    // MARK: - Übernehmen und Sperre

    func testFineTuningAppliesWithoutNewVersionOrLock() throws {
        let store = try store()
        let version = store.goalVersion
        let faster = olympic().settingDiscipline(.init(sport: .run, distanceMeters: 10_000, targetDurationSeconds: 3000), for: .run)

        XCTAssertEqual(store.apply(faster, now: now), .fineTuned)
        XCTAssertEqual(store.goal(), faster)
        XCTAssertEqual(store.goalVersion, version)
        XCTAssertNil(store.lockedUntil(now: now))
        XCTAssertEqual(store.apply(faster, now: now), .unchanged)
    }

    func testNewGoalBumpsTheVersionAndLocksForSevenDays() throws {
        let store = try store()
        let version = store.goalVersion
        let half = olympic().settingDiscipline(.init(sport: .run, distanceMeters: 21_100), for: .run)

        XCTAssertEqual(store.apply(half, now: now), .newGoal)
        XCTAssertEqual(store.goalVersion, version + 1)
        let until = try XCTUnwrap(store.lockedUntil(now: now))
        XCTAssertEqual(until, now.addingTimeInterval(7 * 86_400))

        // Ein weiteres neues Ziel ist gesperrt, eine Feinjustierung nicht.
        let marathon = olympic().settingDiscipline(.init(sport: .run, distanceMeters: 42_195), for: .run)
        XCTAssertEqual(store.apply(marathon, now: now.addingTimeInterval(86_400)), .locked(until: until))
        XCTAssertEqual(store.goal(), half)
        XCTAssertEqual(store.apply(half.settingEmphasis(35, for: .swim), now: now.addingTimeInterval(86_400)), .fineTuned)

        // Nach sieben Tagen geht es wieder.
        XCTAssertNil(store.lockedUntil(now: until))
        XCTAssertEqual(store.apply(marathon, now: until), .newGoal)
        XCTAssertEqual(store.goalVersion, version + 2)
    }

    func testAPastGoalDayLiftsTheLock() throws {
        let store = try store()
        let soon = olympic(daysAhead: 3).settingDiscipline(.init(sport: .run, distanceMeters: 21_100), for: .run)
        XCTAssertEqual(store.apply(soon, now: now), .newGoal)
        XCTAssertNotNil(store.lockedUntil(now: now.addingTimeInterval(2 * 86_400)))
        XCTAssertNil(store.lockedUntil(now: now.addingTimeInterval(4 * 86_400)))
    }

    func testInvalidDraftsAreNotApplied() throws {
        let store = try store()
        var broken = olympic()
        broken.disciplines = []
        guard case .invalid = store.apply(broken, now: now) else { return XCTFail("ungültig erwartet") }
        XCTAssertEqual(store.goal(), olympic())
    }

    func testAPendingDraftIsAppliedWhenTheLockEnds() throws {
        let store = try store()
        let half = olympic().settingDiscipline(.init(sport: .run, distanceMeters: 21_100), for: .run)
        XCTAssertEqual(store.apply(half, now: now), .newGoal)

        let marathon = olympic().settingDiscipline(.init(sport: .run, distanceMeters: 42_195), for: .run)
        store.setPendingGoal(marathon)
        XCTAssertEqual(store.pendingGoal(), marathon)
        XCTAssertFalse(store.applyPendingIfDue(now: now.addingTimeInterval(3 * 86_400)))
        XCTAssertEqual(store.goal(), half)

        XCTAssertTrue(store.applyPendingIfDue(now: now.addingTimeInterval(7 * 86_400)))
        XCTAssertEqual(store.goal(), marathon)
        XCTAssertNil(store.pendingGoal())
        XCTAssertFalse(store.applyPendingIfDue(now: now.addingTimeInterval(8 * 86_400)))
    }

    func testAnOutdatedPendingDraftIsDropped() throws {
        let store = try store()
        let soon = olympic(daysAhead: 2).settingDiscipline(.init(sport: .run, distanceMeters: 21_100), for: .run)
        store.setPendingGoal(soon)
        // Der Zieltag des Entwurfs ist vorbei: ungültig, er verfällt.
        XCTAssertFalse(store.applyPendingIfDue(now: now.addingTimeInterval(3 * 86_400)))
        XCTAssertNil(store.pendingGoal())
    }

    func testSettingAGoalDirectlyBumpsTheVersionOnlyForANewGoal() throws {
        let store = try store()
        let version = store.goalVersion
        XCTAssertTrue(store.setGoal(olympic().settingEmphasis(40, for: .swim), now: now))
        XCTAssertEqual(store.goalVersion, version)
        XCTAssertTrue(store.setGoal(olympic().settingKind(.fitness, now: now), now: now))
        XCTAssertEqual(store.goalVersion, version + 1)
        // Die Einrichtung sperrt nichts.
        XCTAssertNil(store.lockedUntil(now: now))
        store.resetGoal()
        XCTAssertEqual(store.goalVersion, version + 2)
    }
}
