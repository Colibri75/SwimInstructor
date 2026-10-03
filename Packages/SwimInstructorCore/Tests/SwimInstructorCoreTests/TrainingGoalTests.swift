import XCTest
@testable import SwimInstructorCore

final class TrainingGoalTests: XCTestCase {
    private let now = TestFixtures.now
    private var future: Date { now.addingTimeInterval(120 * 86_400) }

    private func olympic() -> TrainingGoal {
        GoalTemplate.template(id: "triathlon_olympic")!.goal(targetDate: future, trainingDaysPerWeek: 5, weeklyHours: 7.5)
    }

    private func problem(_ change: (inout TrainingGoal) -> Void) -> String? {
        var goal = olympic()
        change(&goal)
        return goal.problem(now: now, calendar: TestFixtures.utc)
    }

    // MARK: - Prüfung

    func testTemplatesAndDefaultAreValid() {
        XCTAssertEqual(Set(GoalTemplate.all.map(\.id)).count, GoalTemplate.all.count, "Kennungen doppelt")
        for template in GoalTemplate.all {
            let goal = template.goal(targetDate: future, trainingDaysPerWeek: 4, weeklyHours: 6)
            XCTAssertNil(goal.problem(now: now, calendar: TestFixtures.utc), template.id)
            XCTAssertEqual(goal.template, template.id)
            XCTAssertEqual(goal.emphasis.reduce(0) { $0 + $1.percent }, 100, template.id)
        }
        XCTAssertNil(TrainingGoal.default.problem())
        XCTAssertNil(GoalTemplate.template(id: nil))
        XCTAssertNil(GoalTemplate.template(id: "unbekannt"))
    }

    func testRejectsNonsenseDisciplines() {
        XCTAssertEqual(problem { $0.disciplines = [] }, "Das Ziel braucht mindestens eine Disziplin.")
        XCTAssertEqual(problem { $0.disciplines = Array(repeating: .init(sport: .run, distanceMeters: 5000), count: 9) }, "Höchstens 8 Disziplinen.")
        XCTAssertEqual(problem { $0.disciplines.append(.init(sport: .run, distanceMeters: 5000)) }, "Jede Sportart darf nur einmal im Ziel stehen.")
        XCTAssertEqual(problem { $0.disciplines[0].sport = "kayak" }, "Unbekannte Sportart kayak.")
        XCTAssertEqual(problem { $0.disciplines[2].distanceMeters = 50 }, "Laufen: Die Strecke muss zwischen 100 m und 500 km liegen.")
        XCTAssertEqual(problem { $0.disciplines[2].targetDurationSeconds = 600 }, "Laufen: Strecke und Zielzeit ergeben ein unrealistisches Tempo.")
        XCTAssertNil(problem { $0.disciplines[2].targetDurationSeconds = 50 * 60 })
    }

    func testRejectsNonsenseTrainingAndEmphasis() {
        XCTAssertEqual(problem { $0.trainingDaysPerWeek = 0 }, "Trainingstage: 1 bis 7 pro Woche.")
        XCTAssertEqual(problem { $0.weeklyHours = 0.5 }, "Trainingszeit: 1 bis 30 Stunden pro Woche.")
        XCTAssertEqual(problem { $0.emphasis = [] }, "Jede Sportart braucht genau einen Schwerpunkt.")
        XCTAssertEqual(problem { $0.emphasis.append(.init(sport: .run, percent: 0)) }, "Jede Sportart braucht genau einen Schwerpunkt.")
        XCTAssertEqual(problem { $0.emphasis[0].percent = 101 }, "Schwerpunkte gehen von 0 bis 100 % und nur für bekannte Sportarten.")
        XCTAssertEqual(problem { $0.emphasis.append(.init(sport: "kayak", percent: 0)) }, "Schwerpunkte gehen von 0 bis 100 % und nur für bekannte Sportarten.")
        XCTAssertEqual(problem { $0.emphasis[0].percent = 30 }, "Die Schwerpunkte müssen zusammen 100 % ergeben.")
        XCTAssertEqual(
            problem { $0.emphasis = [.init(sport: .swim, percent: 50), .init(sport: .bike, percent: 50), .init(sport: .run, percent: 0)] },
            "Laufen gehört zum Ziel und braucht einen Schwerpunkt über 0 %."
        )
    }

    func testTargetDayMustBeInTheFutureOnlyWhenSettingAGoal() {
        XCTAssertEqual(problem { $0.targetDate = now }, "Der Zieltag muss in der Zukunft liegen.")
        XCTAssertEqual(problem { $0.targetDate = now.addingTimeInterval(-86_400) }, "Der Zieltag muss in der Zukunft liegen.")
        XCTAssertNil(problem { $0.targetDate = now.addingTimeInterval(86_400) })
        // Ein gespeichertes Ziel bleibt gültig, wenn sein Tag vorbei ist.
        var past = olympic()
        past.targetDate = now.addingTimeInterval(-86_400)
        XCTAssertNil(past.problem())
    }

    // MARK: - Bearbeiten

    func testSettingEmphasisRebalancesTheOthersProportionally() {
        let goal = olympic() // 25 / 45 / 30
        XCTAssertEqual(goal.settingEmphasis(40, for: .swim).emphasis.map(\.percent), [40, 36, 24])
        // 67 auf 45:30 verteilt ergibt 40,2 und 26,8; der Rundungsrest geht an Rad.
        XCTAssertEqual(goal.settingEmphasis(33, for: .swim).emphasis.map(\.percent), [33, 41, 26])
        XCTAssertEqual(goal.settingEmphasis(100, for: .run).emphasis.map(\.percent), [0, 0, 100])
        // 100 auf 25:45 verteilt ergibt 35,7 und 64,3; abgerundet 35 und 64, der Rest geht an Rad.
        XCTAssertEqual(goal.settingEmphasis(-5, for: .run).emphasis.map(\.percent), [35, 65, 0])
        XCTAssertEqual(goal.settingEmphasis(40, for: .swim).emphasis.map(\.sport), [.swim, .bike, .run])
    }

    func testSettingEmphasisWithoutPreviousSharesAndForNewSports() {
        var goal = olympic()
        goal.emphasis = [.init(sport: .swim, percent: 100), .init(sport: .bike, percent: 0), .init(sport: .run, percent: 0)]
        XCTAssertEqual(goal.settingEmphasis(40, for: .swim).emphasis.map(\.percent), [40, 30, 30])

        goal.emphasis = [.init(sport: .run, percent: 100)]
        XCTAssertEqual(goal.settingEmphasis(50, for: .run).emphasis, [.init(sport: .run, percent: 100)])
        XCTAssertEqual(goal.settingEmphasis(20, for: .swim).emphasis, [.init(sport: .swim, percent: 20), .init(sport: .run, percent: 80)])
    }

    func testSettingDisciplineAddsReplacesAndRemoves() {
        let run = GoalTemplate.template(id: "run_10k")!.goal(targetDate: future, trainingDaysPerWeek: 4, weeklyHours: 5)

        let withBike = run.settingDiscipline(.init(sport: .bike, distanceMeters: 40_000), for: .bike)
        XCTAssertNil(withBike.template)
        XCTAssertEqual(withBike.disciplines.map(\.sport), [.bike, .run])
        XCTAssertEqual(withBike.emphasis, [.init(sport: .bike, percent: 50), .init(sport: .run, percent: 50)])
        XCTAssertNil(withBike.problem(now: now, calendar: TestFixtures.utc))

        let longer = withBike.settingDiscipline(.init(sport: .bike, distanceMeters: 90_000, targetDurationSeconds: 3 * 3600), for: .bike)
        XCTAssertEqual(longer.discipline(for: .bike)?.distanceMeters, 90_000)
        XCTAssertEqual(longer.emphasis, withBike.emphasis, "Schwerpunkt bleibt, wenn die Disziplin schon einen hat")

        let without = longer.settingDiscipline(nil, for: .bike)
        XCTAssertEqual(without.disciplines.map(\.sport), [.run])
        XCTAssertEqual(without.percent(for: .bike), 50, "Rad darf weiter trainiert werden, ohne Disziplin zu sein")
        XCTAssertNil(without.problem(now: now, calendar: TestFixtures.utc))
    }

    // MARK: - Altes Schwimmziel

    func testLegacyGoalBecomesASwimOnlyTrainingGoal() {
        XCTAssertEqual(TrainingGoal.default.template, "swim_long")
        XCTAssertEqual(TrainingGoal.default.disciplines, [.init(sport: .swim, distanceMeters: 3800, targetDurationSeconds: 3600)])
        XCTAssertEqual(TrainingGoal.default.emphasis, [.init(sport: .swim, percent: 100)])
        XCTAssertEqual(TrainingGoal.default.targetDate, AthleteGoal.default.targetDate)
        XCTAssertEqual(TrainingGoal.default.legacySwimGoal, AthleteGoal.default)

        let custom = TrainingGoal(legacy: AthleteGoal(distanceMeters: 2000, targetDurationSeconds: 2700, targetDate: future))
        XCTAssertNil(custom.template)
        XCTAssertEqual(custom.trainingDaysPerWeek, 4)
        XCTAssertEqual(custom.weeklyHours, 4)
    }

    func testLegacySwimGoalForTheServerUntilT3() {
        let goal = olympic()
        // Schwimm-Disziplin ohne Zielzeit: 2:00 pro 100 m.
        XCTAssertEqual(goal.legacySwimGoal, AthleteGoal(distanceMeters: 1500, targetDurationSeconds: 1800, targetDate: future))
        let timed = goal.settingDiscipline(.init(sport: .swim, distanceMeters: 1500, targetDurationSeconds: 1500), for: .swim)
        XCTAssertEqual(timed.legacySwimGoal.targetDurationSeconds, 1500)
        // Ohne Schwimmen: Platzhalter, gültig für den Server.
        let marathon = GoalTemplate.template(id: "run_marathon")!.goal(targetDate: future, trainingDaysPerWeek: 5, weeklyHours: 6)
        XCTAssertEqual(marathon.legacySwimGoal, AthleteGoal(distanceMeters: 1500, targetDurationSeconds: 2700, targetDate: future))
        XCTAssertNil(marathon.legacySwimGoal.problem)
    }

    func testCodableKeepsAllFields() throws {
        let goal = olympic().settingDiscipline(.init(sport: .bike, distanceMeters: 40_000, targetDurationSeconds: 4800), for: .bike)
        let decoded = try JSONDecoder().decode(TrainingGoal.self, from: JSONEncoder().encode(goal))
        XCTAssertEqual(decoded, goal)
        XCTAssertEqual(goal.discipline(for: .bike)?.id, .bike)
    }

    func testSummaryForSettings() {
        XCTAssertEqual(PlanFormatting.goalSummary(olympic(), calendar: TestFixtures.utc), "Triathlon Olympisch, 28.01.2027")
        let custom = olympic().settingDiscipline(nil, for: .swim)
        XCTAssertEqual(PlanFormatting.goalSummary(custom, calendar: TestFixtures.utc), "Radfahren 40,0 km, Laufen 10,0 km, 28.01.2027")
    }
}
