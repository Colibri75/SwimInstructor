import XCTest
@testable import SwimInstructorCore

/// Die Dateien von Plan v2 auf dem Gerät: Tagesplan, Verlauf, sieben Tage und Gesamtplan.
final class PlanV2StoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-v2-stores-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Hilfen

    private func file(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    private func writeGarbage(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("kein json".utf8).write(to: url)
    }

    private static func response(date: String, source: PlanSource = .claude, rationale: String = "Locker schwimmen") -> DayPlanV2Response {
        let step = PlanStep(
            name: "Hauptsatz",
            repetitions: 3,
            measure: .distance,
            distanceMeters: 500,
            targetType: .pacePerHundredMeters,
            targetValue: 130,
            restSeconds: 30,
            instructions: "gleichmäßig",
            cue: "Gleichmäßig",
            equipment: ["pull_buoy"]
        )
        let session = DaySession(
            sport: .swim,
            sessionType: .endurance,
            intensity: .easy,
            focus: "Grundlage",
            amount: 1500,
            unit: .meters,
            distanceMeters: 1500,
            durationMinutes: 35,
            steps: [step]
        )
        return DayPlanV2Response(
            source: source,
            date: date,
            generatedAt: TestFixtures.now,
            stale: source == .fallback,
            plan: DayPlanV2(rationale: rationale, sessions: [session], coachNotes: ["Viel trinken"]),
            fallbackReason: source == .fallback ? "timeout" : nil
        )
    }

    private static func weekSession(_ sport: SportID, minutes: Double, test: PlannedTest? = nil) -> WeekSession {
        WeekSession(
            sport: sport,
            sessionType: test == nil ? .endurance : .test,
            intensity: test == nil ? .easy : .hard,
            amount: minutes,
            unit: .minutes,
            minutes: minutes,
            distanceMeters: minutes * 300,
            focus: "Grundlage",
            test: test
        )
    }

    private static func macroPlan(rounds: [MacroFeedbackRound]) -> MacroPlanV2 {
        let week = MacroWeekV2(
            weekStart: "2026-09-28",
            phase: .specific,
            deload: false,
            focus: "Wettkampfnah",
            totalMinutes: 210,
            load: 190,
            sports: [MacroSportVolume(sport: .bike, unit: .minutes, amount: 100, minutes: 100, distanceMeters: 45900, sessions: 2)],
            tests: [MacroTestSlot(sport: .bike, testID: "threshold_30min", displayName: "30-Minuten-Test")]
        )
        return MacroPlanV2(
            goalKey: "ziel",
            goalDay: "2026-11-08",
            generatedAt: TestFixtures.now,
            rationale: "Sechs Wochen bis zum Ziel.",
            adjustments: ["gekürzt"],
            weeks: [week],
            feedbackRounds: rounds
        )
    }

    // MARK: - Tagesplan

    func testDayCacheIsEmptyWithoutFile() {
        XCTAssertNil(FileDayPlanV2Cache(fileURL: file("last-plan-v2.json")).load())
    }

    func testDayCacheKeepsTheLastPlanFromTheServer() throws {
        let response = try PlanResponse.jsonDecoder().decode(
            DayPlanV2Response.self, from: RepoPaths.contractData("wire/plan-v2-today-response.json")
        )
        // Unterordner, die noch fehlen, werden angelegt.
        let url = file("SwimInstructor/last-plan-v2.json")

        try FileDayPlanV2Cache(fileURL: url).save(response)

        XCTAssertEqual(FileDayPlanV2Cache(fileURL: url).load(), response)

        let newer = Self.response(date: "2026-10-01")
        try FileDayPlanV2Cache(fileURL: url).save(newer)

        XCTAssertEqual(FileDayPlanV2Cache(fileURL: url).load(), newer)
    }

    func testDayCacheWithCorruptFileHasNoPlan() throws {
        let url = file("last-plan-v2.json")
        try writeGarbage(to: url)

        XCTAssertNil(FileDayPlanV2Cache(fileURL: url).load())
    }

    // MARK: - Verlauf

    func testHistoryIsEmptyWithoutFileAndLegacy() {
        XCTAssertEqual(FileDayPlanV2History(fileURL: file("plan-history-v2.json")).load(), [])
    }

    func testHistoryKeepsPlansOldestFirstAcrossInstances() throws {
        let history = FileDayPlanV2History(fileURL: file("plan-history-v2.json"))

        try history.record(Self.response(date: "2026-09-30"))
        try history.record(Self.response(date: "2026-09-28"))
        try history.record(Self.response(date: "2026-09-29"))

        let reloaded = FileDayPlanV2History(fileURL: file("plan-history-v2.json")).load()
        XCTAssertEqual(reloaded.map(\.date), ["2026-09-28", "2026-09-29", "2026-09-30"])
        XCTAssertEqual(reloaded.first, Self.response(date: "2026-09-28"))
    }

    func testFirstPlanOfADayWins() throws {
        let history = FileDayPlanV2History(fileURL: file("plan-history-v2.json"))
        let morning = Self.response(date: "2026-09-30", rationale: "Morgens")
        let evening = Self.response(date: "2026-09-30", source: .cache, rationale: "Abends")

        try history.record(morning)
        try history.record(evening)

        XCTAssertEqual(history.load(), [morning])
    }

    func testFallbackPlansAreNotRecorded() throws {
        let url = file("plan-history-v2.json")
        let history = FileDayPlanV2History(fileURL: url)

        try history.record(Self.response(date: "2026-09-29", source: .fallback))

        XCTAssertEqual(history.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testOldestEntriesFallOutBeyondTheLimit() throws {
        let history = FileDayPlanV2History(fileURL: file("plan-history-v2.json"), maxEntries: 3)

        for day in 1...5 {
            try history.record(Self.response(date: String(format: "2026-09-%02d", day)))
        }

        XCTAssertEqual(history.load().map(\.date), ["2026-09-03", "2026-09-04", "2026-09-05"])
        XCTAssertEqual(FileDayPlanV2History.defaultMaxEntries, 120)
    }

    func testCorruptHistoryCountsAsEmptyAndIsReplacedOnNextRecord() throws {
        let url = file("plan-history-v2.json")
        try writeGarbage(to: url)
        let history = FileDayPlanV2History(fileURL: url)

        XCTAssertEqual(history.load(), [])
        try history.record(Self.response(date: "2026-09-30"))

        XCTAssertEqual(history.load().map(\.date), ["2026-09-30"])
    }

    func testLegacyHistoryFillsDaysWithoutAV2Plan() throws {
        let legacy = FilePlanHistory(fileURL: file("plan-history.json"))
        try legacy.record(TestFixtures.response(date: "2026-09-27"))
        try legacy.record(TestFixtures.response(date: "2026-09-28"))
        let ownURL = file("plan-history-v2.json")
        let history = FileDayPlanV2History(fileURL: ownURL, legacy: legacy)

        try history.record(Self.response(date: "2026-09-28"))
        try history.record(Self.response(date: "2026-09-29"))
        let loaded = history.load()

        // Für den 28. gibt es beides: Der v2-Plan geht vor.
        XCTAssertEqual(loaded.map(\.date), ["2026-09-27", "2026-09-28", "2026-09-29"])
        XCTAssertEqual(loaded.map(\.planVersion), [1, 2, 2])
        XCTAssertEqual(loaded[1], Self.response(date: "2026-09-28"))

        // Der umgewandelte Plan v1: eine Schwimmeinheit.
        let converted = loaded[0]
        XCTAssertEqual(converted, DayPlanV2Response(legacy: TestFixtures.response(date: "2026-09-27")))
        XCTAssertEqual(converted.plan.sessions.map(\.sport), [.swim])
        XCTAssertEqual(converted.plan.sessions.first?.distanceMeters, 800)
        XCTAssertEqual(converted.plan.sessions.first?.steps.first?.totalMeters, 800)

        // Die umgewandelten Pläne landen nicht in der eigenen Datei, der alte Verlauf bleibt unverändert.
        XCTAssertEqual(FileDayPlanV2History(fileURL: ownURL).load().map(\.date), ["2026-09-28", "2026-09-29"])
        XCTAssertEqual(legacy.load().map(\.date), ["2026-09-27", "2026-09-28"])
    }

    func testLegacyHistoryAloneIsShownConverted() throws {
        let legacy = FilePlanHistory(fileURL: file("plan-history.json"))
        try legacy.record(TestFixtures.response(date: "2026-09-29"))
        try legacy.record(TestFixtures.response(date: "2026-09-27"))

        let loaded = FileDayPlanV2History(fileURL: file("plan-history-v2.json"), legacy: legacy).load()

        XCTAssertEqual(loaded.map(\.date), ["2026-09-27", "2026-09-29"])
        XCTAssertEqual(loaded.map(\.planVersion), [1, 1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file("plan-history-v2.json").path))
    }

    // MARK: - Sieben Tage

    func testWeekStoreIsEmptyWithoutFile() {
        XCTAssertEqual(FileWeekPlanV2Store(fileURL: file("week-plans-v2.json")).load(), [])
    }

    func testWeekStoreKeepsPlansSortedWithTheAthleteChanges() throws {
        let bikeTest = PlannedTest(id: "threshold_30min", displayName: "30-Minuten-Test", maximalEffort: true, produces: [.thresholdHeartRate, .thresholdPower])
        let remembered = PlannedDayContent(focus: "Rad", sessions: [Self.weekSession(.bike, minutes: 58, test: bikeTest)])
        let later = WeekPlanV2(
            weekStart: "2026-10-05",
            generatedAt: TestFixtures.now,
            rationale: "Zweite Woche",
            adjustments: ["Umfang gekürzt"],
            wishes: "mehr Rad",
            days: [
                PlannedDay(date: "2026-10-06", content: .rest(focus: "Keine Zeit"), isUnavailable: true, contentBeforeUnavailable: remembered, isEdited: true),
                PlannedDay(date: "2026-10-05", content: PlannedDayContent(focus: "Lauf und Schwimmen", sessions: [Self.weekSession(.run, minutes: 40), Self.weekSession(.swim, minutes: 30)]))
            ]
        )
        let earlier = WeekPlanV2(
            weekStart: "2026-09-28",
            generatedAt: TestFixtures.now.addingTimeInterval(-86_400),
            rationale: "Erste Woche",
            days: [PlannedDay(date: "2026-09-30", content: .rest())]
        )
        let url = file("week-plans-v2.json")

        try FileWeekPlanV2Store(fileURL: url).save([later, earlier])
        let loaded = FileWeekPlanV2Store(fileURL: url).load()

        XCTAssertEqual(loaded.map(\.weekStart), ["2026-09-28", "2026-10-05"])
        XCTAssertEqual(loaded, [earlier, later])
        let blocked = loaded.last?.day(on: "2026-10-06")
        XCTAssertEqual(blocked?.isUnavailable, true)
        XCTAssertEqual(blocked?.isEdited, true)
        XCTAssertEqual(blocked?.contentBeforeUnavailable, remembered)
        XCTAssertEqual(blocked?.contentBeforeUnavailable?.sessions.first?.test?.id, "threshold_30min")
        XCTAssertEqual(loaded.last?.wishes, "mehr Rad")
        XCTAssertEqual(loaded.last?.adjustments, ["Umfang gekürzt"])

        // Speichern ersetzt die Datei.
        try FileWeekPlanV2Store(fileURL: url).save([])
        XCTAssertEqual(FileWeekPlanV2Store(fileURL: url).load(), [])
    }

    func testWeekStoreWithCorruptFileIsEmpty() throws {
        let url = file("week-plans-v2.json")
        try writeGarbage(to: url)

        XCTAssertEqual(FileWeekPlanV2Store(fileURL: url).load(), [])
    }

    // MARK: - Gesamtplan

    func testMacroStoreIsEmptyWithoutFile() {
        XCTAssertNil(FileMacroPlanV2Store(fileURL: file("macro-plan-v2.json")).load())
    }

    func testMacroStoreKeepsThePlanWithItsRounds() throws {
        let round = MacroFeedbackRound(
            feedback: "Mehr Laufen bitte",
            changes: ["Laufen 5 Minuten mehr"],
            adjustments: ["Schwimmen begrenzt"],
            revisedAt: TestFixtures.now
        )
        let plan = Self.macroPlan(rounds: [round])
        let url = file("SwimInstructor/macro-plan-v2.json")

        try FileMacroPlanV2Store(fileURL: url).save(plan)
        let loaded = try XCTUnwrap(FileMacroPlanV2Store(fileURL: url).load())

        XCTAssertEqual(loaded, plan)
        XCTAssertEqual(loaded.feedbackRounds, [round])
        XCTAssertEqual(loaded.weeks.first?.tests.first?.testID, "threshold_30min")
    }

    func testMacroStoreKeepsAPlanFromTheServer() throws {
        let response = try PlanResponse.jsonDecoder().decode(
            MacroPlanV2Response.self, from: RepoPaths.contractData("wire/plan-v2-macro-response.json")
        )
        let plan = response.macroPlan(goalKey: "ziel")
        let url = file("macro-plan-v2.json")

        try FileMacroPlanV2Store(fileURL: url).save(plan)

        XCTAssertEqual(FileMacroPlanV2Store(fileURL: url).load(), plan)
    }

    func testMacroStoreWithCorruptFileHasNoPlan() throws {
        let url = file("macro-plan-v2.json")
        try writeGarbage(to: url)

        XCTAssertNil(FileMacroPlanV2Store(fileURL: url).load())
    }
}
