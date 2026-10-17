import XCTest
@testable import SwimInstructorCore

@MainActor
final class OnboardingPlanBuilderTests: XCTestCase {
    func testRunsAllStepsInOrderAndFinishes() async {
        var calls: [String] = []
        let builder = OnboardingPlanBuilder(
            health: { calls.append("health"); return nil },
            macro: { calls.append("macro"); return nil },
            days: { calls.append("days"); return nil },
            today: { calls.append("today"); return nil }
        )
        XCTAssertNil(builder.step)
        await builder.run()
        XCTAssertEqual(calls, ["health", "macro", "days", "today"])
        XCTAssertTrue(builder.isFinished)
        XCTAssertNil(builder.failure)
        XCTAssertTrue(OnboardingPlanBuilder.Step.allCases.allSatisfy(builder.isDone))
    }

    /// Ein gescheiterter Gesamtplan zeigt den Fehler und geht nicht weiter, statt mit leerem Plan in die App zu lassen.
    func testStopsAtTheFailedStepAndRetries() async {
        var macroFails = true
        var calls: [String] = []
        let builder = OnboardingPlanBuilder(
            health: { calls.append("health"); return nil },
            macro: { calls.append("macro"); return macroFails ? "Kein neuer Plan" : nil },
            days: { calls.append("days"); return nil },
            today: { calls.append("today"); return nil }
        )
        await builder.run()
        XCTAssertFalse(builder.isFinished)
        XCTAssertEqual(builder.failure, "Kein neuer Plan")
        XCTAssertEqual(builder.step, .macro)
        XCTAssertTrue(builder.isDone(.health))
        XCTAssertFalse(builder.isDone(.macro))
        XCTAssertEqual(calls, ["health", "macro"])

        macroFails = false
        await builder.run()
        XCTAssertTrue(builder.isFinished)
        XCTAssertNil(builder.failure)
        XCTAssertEqual(calls, ["health", "macro", "health", "macro", "days", "today"])
    }
}
