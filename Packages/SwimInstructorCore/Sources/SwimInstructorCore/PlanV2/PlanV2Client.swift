import Foundation

// MARK: - Leistungstests

/// Leistungstests im Plan: ob der Server sie anbietet, in welchem Abstand er sie wiederholt und welchen Test der Athlet
/// je Sportart bevorzugt. Geht als `test_settings` mit jeder Anfrage von Plan v2.
public struct TestSettings: Codable, Equatable, Sendable {
    public struct Preference: Codable, Equatable, Sendable {
        public let sport: SportID
        public let testID: String

        public init(sport: SportID, testID: String) {
            self.sport = sport
            self.testID = testID
        }

        private enum CodingKeys: String, CodingKey {
            case sport
            case testID = "testId"
        }
    }

    /// Tests anbieten (Standard ja). Ohne Angebot plant der Server keine Tests ein.
    public var offer: Bool
    /// Abstand der Wiederholungen in Wochen.
    public var intervalWeeks: Int
    public var preferred: [Preference]

    /// Was der Server als Abstand annimmt.
    public static let intervalRange: ClosedRange<Int> = 4...12
    /// Tests angeboten, alle 6 Wochen, ohne bevorzugten Test.
    public static let standard = TestSettings(offer: true, intervalWeeks: 6, preferred: [])

    public init(offer: Bool, intervalWeeks: Int, preferred: [Preference] = []) {
        self.offer = offer
        self.intervalWeeks = min(max(intervalWeeks, Self.intervalRange.lowerBound), Self.intervalRange.upperBound)
        self.preferred = preferred
    }

    /// Der bevorzugte Test einer Sportart, `nil` ohne Vorliebe.
    public func preferredTest(for sport: SportID) -> String? {
        preferred.first { $0.sport == sport }?.testID
    }

    /// Dieselben Einstellungen mit einem anderen bevorzugten Test (`nil`: keine Vorliebe) für die Sportart.
    public func preferring(_ testID: String?, for sport: SportID) -> TestSettings {
        var copy = self
        copy.preferred = preferred.filter { $0.sport != sport } + (testID.map { [Preference(sport: sport, testID: $0)] } ?? [])
        return copy
    }
}

public protocol TestSettingsStoring {
    func settings() -> TestSettings
    func save(_ settings: TestSettings)
}

public struct UserDefaultsTestSettingsStore: TestSettingsStoring {
    static let storageKey = "settings.testSettings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func settings() -> TestSettings {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(TestSettings.self, from: data) else { return .standard }
        // Über den Initialisierer, damit ein gespeicherter Abstand außerhalb des erlaubten Bereichs eingefangen wird.
        return TestSettings(offer: stored.offer, intervalWeeks: stored.intervalWeeks, preferred: stored.preferred)
    }

    public func save(_ settings: TestSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Bisheriges Training

/// Eine Einheit der letzten Tage, wie sie mit Plan v2 an den Server geht (`recent_training`). Sie zählt für "nie zwei
/// harte Tage hintereinander" und die Grenzen von heute.
public struct RecentTrainingEntry: Codable, Equatable, Sendable {
    public let date: String
    public let sport: SportID
    public let minutes: Double
    public let meters: Double
    public let hard: Bool

    public init(date: String, sport: SportID, minutes: Double, meters: Double, hard: Bool) {
        self.date = date
        self.sport = sport
        self.minutes = minutes
        self.meters = meters
        self.hard = hard
    }
}

public enum RecentTraining {
    /// Höchstens so viele Einheiten nimmt der Server an.
    public static let maximumEntries = 40
    /// Ab diesem Anteil des Maximalpulses im Schnitt gilt eine Einheit als hart, auch ohne harten Plan.
    public static let hardHeartRateShare = 0.88

    /// Die Einheiten von `start` (einschließlich) bis vor `end`, je Einheit, ältere zuerst; bei mehr als
    /// `maximumEntries` die neuesten. Hart ist eine Einheit, wenn der Plan für ihren Tag in ihrer Sportart eine harte
    /// Einheit vorsah oder ihr Puls im Schnitt bei mindestens 88 % des Maximalpulses lag. Sportarten, die die App nicht
    /// kennt, fallen weg (der Server lehnt sie ab).
    public static func entries(
        workouts: [Workout],
        from start: String,
        before end: String,
        plannedHard: (String, SportID) -> Bool = { _, _ in false },
        maximumHeartRate: Double? = nil,
        registry: SportRegistry = .standard,
        calendar: Calendar = .current
    ) -> [RecentTrainingEntry] {
        let entries = workouts
            .sorted { $0.startDate < $1.startDate }
            .compactMap { workout -> RecentTrainingEntry? in
                let date = PlanFormatting.isoDay(workout.startDate, calendar: calendar)
                guard date >= start, date < end, registry.module(for: workout.sport) != nil else { return nil }
                var heartRateHard = false
                if let heartRate = workout.averageHeartRate, let maximumHeartRate {
                    heartRateHard = heartRate >= maximumHeartRate * Self.hardHeartRateShare
                }
                return RecentTrainingEntry(
                    date: date,
                    sport: workout.sport,
                    minutes: min(max(workout.duration / 60, 0), 1440).rounded(),
                    meters: min(max(workout.distanceMeters ?? 0, 0), 1_000_000).rounded(),
                    hard: plannedHard(date, workout.sport) || heartRateHard
                )
            }
        return Array(entries.suffix(maximumEntries))
    }
}

// MARK: - Anfragen

/// Anfrage für den Tagesplan v2 (`POST /v1/plan/today` mit `plan_version: 2`).
public struct DayPlanV2Request: Equatable, Sendable {
    public var snapshot: AthleteStateSnapshot
    /// Claude auch dann neu fragen, wenn für denselben Zustand heute schon ein Plan vorliegt.
    public var regenerate: Bool
    public var wishes: String?
    /// Vorgabe des Wochenplans für heute.
    public var dayPlan: DayTargetV2?
    public var equipment: [String]?
    public var recentTraining: [RecentTrainingEntry]
    public var testSettings: TestSettings?

    public init(
        snapshot: AthleteStateSnapshot,
        regenerate: Bool = false,
        wishes: String? = nil,
        dayPlan: DayTargetV2? = nil,
        equipment: [String]? = nil,
        recentTraining: [RecentTrainingEntry] = [],
        testSettings: TestSettings? = nil
    ) {
        self.snapshot = snapshot
        self.regenerate = regenerate
        self.wishes = wishes
        self.dayPlan = dayPlan
        self.equipment = equipment
        self.recentTraining = recentTraining
        self.testSettings = testSettings
    }
}

/// Anfrage für die nächsten sieben Tage v2 (`POST /v1/plan/week` mit `plan_version: 2`).
public struct WeekPlanV2Request: Equatable, Sendable {
    public var snapshot: AthleteStateSnapshot
    /// Erster der sieben Tage, meist heute.
    public var fromDate: String
    public var today: String
    /// Tage ohne Zeit, sie werden Ruhetage.
    public var unavailableDates: [String]
    public var recentTraining: [RecentTrainingEntry]
    /// Die Wochen des Gesamtplans, in die die sieben Tage fallen (höchstens drei gehen mit).
    public var macroWeeks: [MacroWeekV2]
    public var wishes: String?
    public var equipment: [String]?
    public var testSettings: TestSettings?

    public init(
        snapshot: AthleteStateSnapshot,
        fromDate: String,
        today: String,
        unavailableDates: [String] = [],
        recentTraining: [RecentTrainingEntry] = [],
        macroWeeks: [MacroWeekV2] = [],
        wishes: String? = nil,
        equipment: [String]? = nil,
        testSettings: TestSettings? = nil
    ) {
        self.snapshot = snapshot
        self.fromDate = fromDate
        self.today = today
        self.unavailableDates = unavailableDates
        self.recentTraining = recentTraining
        self.macroWeeks = macroWeeks
        self.wishes = wishes
        self.equipment = equipment
        self.testSettings = testSettings
    }
}

/// Anfrage für den Gesamtplan v2 (`POST /v1/plan/macro` mit `plan_version: 2`).
public struct MacroPlanV2Request: Equatable, Sendable {
    public var snapshot: AthleteStateSnapshot
    public var today: String
    public var testSettings: TestSettings?

    public init(snapshot: AthleteStateSnapshot, today: String, testSettings: TestSettings? = nil) {
        self.snapshot = snapshot
        self.today = today
        self.testSettings = testSettings
    }
}

/// Feedback zum Gesamtplan (`POST /v1/plan/macro/revise`): der Plan, wie die App ihn hält, das Feedback und die
/// bisherigen Runden.
public struct MacroRevisionRequest: Equatable, Sendable {
    public static let maxFeedbackLength = 1000
    /// So viele frühere Runden gehen mit.
    public static let maxHistory = 5

    public var snapshot: AthleteStateSnapshot
    public var today: String
    public var plan: MacroPlanV2
    public var feedback: String
    public var testSettings: TestSettings?

    public init(snapshot: AthleteStateSnapshot, today: String, plan: MacroPlanV2, feedback: String, testSettings: TestSettings? = nil) {
        self.snapshot = snapshot
        self.today = today
        self.plan = plan
        self.feedback = feedback
        self.testSettings = testSettings
    }
}

/// Fortschreibung des Gesamtplans (`POST /v1/plan/macro/review`, P4): der Plan, das Ist der letzten Wochen, der Anlass,
/// eine gemeldete Pause und optional Feedback.
public struct MacroReviewRequest: Equatable, Sendable {
    /// So viele vergangene Wochen gehen höchstens als Ist mit.
    public static let maxActualWeeks = 12

    public var snapshot: AthleteStateSnapshot
    public var today: String
    public var plan: MacroPlanV2
    /// Nur die Wochen ab hier gehen als bisheriger Plan mit (vergangene Wochen bleiben sonst unbegrenzt im Plan).
    public var planFrom: String
    public var actual: [MacroActualWeek]
    public var reason: MacroReviewReason
    public var pause: PauseReport?
    public var feedback: String?
    /// Bestätigte Leistungswerte seit dem letzten Stand des Plans.
    public var performanceChanges: [PerformanceChange]
    public var testSettings: TestSettings?

    public init(
        snapshot: AthleteStateSnapshot,
        today: String,
        plan: MacroPlanV2,
        planFrom: String,
        actual: [MacroActualWeek],
        reason: MacroReviewReason,
        pause: PauseReport? = nil,
        feedback: String? = nil,
        performanceChanges: [PerformanceChange] = [],
        testSettings: TestSettings? = nil
    ) {
        self.snapshot = snapshot
        self.today = today
        self.plan = plan
        self.planFrom = planFrom
        self.actual = actual
        self.reason = reason
        self.pause = pause
        self.feedback = feedback
        self.performanceChanges = performanceChanges
        self.testSettings = testSettings
    }
}

public protocol DayPlanV2Providing: Sendable {
    func fetchDayPlanV2(_ request: DayPlanV2Request) async throws -> DayPlanV2Response
}

public protocol WeekPlanV2Providing: Sendable {
    func fetchWeekPlanV2(_ request: WeekPlanV2Request) async throws -> WeekPlanV2Response
}

public protocol MacroPlanV2Providing: Sendable {
    func fetchMacroPlanV2(_ request: MacroPlanV2Request) async throws -> MacroPlanV2Response
    func reviseMacroPlan(_ request: MacroRevisionRequest) async throws -> MacroPlanV2Response
    func reviewMacroPlan(_ request: MacroReviewRequest) async throws -> MacroPlanV2Response
}

// MARK: - Client

extension PlanAPIClient: DayPlanV2Providing, WeekPlanV2Providing, MacroPlanV2Providing {
    static let planVersion = 2

    public func fetchDayPlanV2(_ request: DayPlanV2Request) async throws -> DayPlanV2Response {
        try await postV2(path: "v1/plan/today", body: DayBody(
            planVersion: Self.planVersion,
            snapshot: request.snapshot,
            regenerate: request.regenerate ? true : nil,
            wishes: Self.cleaned(request.wishes),
            dayPlan: request.dayPlan,
            equipment: request.equipment,
            recentTraining: request.recentTraining.isEmpty ? nil : request.recentTraining,
            testSettings: request.testSettings
        ))
    }

    public func fetchWeekPlanV2(_ request: WeekPlanV2Request) async throws -> WeekPlanV2Response {
        try await postV2(path: "v1/plan/week", body: WeekBody(
            planVersion: Self.planVersion,
            snapshot: request.snapshot,
            fromDate: request.fromDate,
            today: request.today,
            unavailableDates: request.unavailableDates,
            recentTraining: request.recentTraining,
            macroWeeks: request.macroWeeks.isEmpty ? nil : Array(request.macroWeeks.prefix(3)),
            wishes: Self.cleaned(request.wishes),
            equipment: request.equipment,
            testSettings: request.testSettings
        ))
    }

    public func fetchMacroPlanV2(_ request: MacroPlanV2Request) async throws -> MacroPlanV2Response {
        try await postV2(path: "v1/plan/macro", timeout: Self.macroTimeout, body: MacroBody(
            planVersion: Self.planVersion, snapshot: request.snapshot, today: request.today, testSettings: request.testSettings
        ))
    }

    public func reviseMacroPlan(_ request: MacroRevisionRequest) async throws -> MacroPlanV2Response {
        let feedback = request.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty else { throw PlanAPIError.invalidRequest(details: ["feedback: leer"]) }
        let history = request.plan.feedbackRounds.suffix(MacroRevisionRequest.maxHistory).map { round in
            ReviseBody.Round(
                feedback: String(round.feedback.prefix(MacroRevisionRequest.maxFeedbackLength)),
                changes: round.changes.prefix(8).map { String($0.prefix(300)) }
            )
        }
        return try await postV2(path: "v1/plan/macro/revise", timeout: Self.macroTimeout, body: ReviseBody(
            planVersion: Self.planVersion,
            snapshot: request.snapshot,
            today: request.today,
            plan: ReviseBody.Plan(rationale: String(request.plan.rationale.prefix(2000)), weeks: Array(request.plan.weeks.prefix(80))),
            feedback: String(feedback.prefix(MacroRevisionRequest.maxFeedbackLength)),
            history: history.isEmpty ? nil : Array(history),
            testSettings: request.testSettings
        ))
    }

    public func reviewMacroPlan(_ request: MacroReviewRequest) async throws -> MacroPlanV2Response {
        let feedback = request.feedback?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await postV2(path: "v1/plan/macro/review", timeout: Self.macroTimeout, body: ReviewBody(
            planVersion: Self.planVersion,
            snapshot: request.snapshot,
            today: request.today,
            plan: ReviseBody.Plan(
                rationale: String(request.plan.rationale.prefix(2000)),
                weeks: Array(request.plan.weeks(from: request.planFrom).prefix(80))
            ),
            actual: request.actual.suffix(MacroReviewRequest.maxActualWeeks).map { week in
                ReviewBody.Week(weekStart: week.weekStart, sports: week.sports.prefix(16).map { .init(sport: $0.sport, amount: $0.amount, sessions: min($0.sessions, 30)) })
            },
            reason: request.reason.rawValue,
            pause: request.pause.map { ReviewBody.Pause(from: $0.from, to: $0.to, kind: $0.kind.rawValue) },
            feedback: (feedback?.isEmpty ?? true) ? nil : feedback.map { String($0.prefix(MacroRevisionRequest.maxFeedbackLength)) },
            performanceChanges: request.performanceChanges.isEmpty ? nil : request.performanceChanges.prefix(20).map {
                ReviewBody.Change(
                    sport: $0.sport, metric: $0.metric.rawValue, previous: $0.previous, value: $0.value, source: $0.source.rawValue, measuredAt: $0.measuredAt
                )
            },
            testSettings: request.testSettings
        ))
    }

    /// Schickt eine Anfrage von Plan v2. Anders als v1 ohne Rückfall auf Snapshot v1: Plan v2 braucht Snapshot v2. Ein
    /// Server ohne Plan v2 antwortet mit einem Plan v1 (ohne `plan_version`) oder kennt den Pfad nicht (404); beides
    /// heißt "Server aktualisieren".
    func postV2<Body: Encodable, Response: Decodable>(
        path: String,
        timeout: TimeInterval = PlanAPIClient.planTimeout,
        body: Body
    ) async throws -> Response {
        let (data, response) = try await post(path: path, body: try AthleteStateSnapshot.jsonEncoder().encode(body), timeout: timeout)
        switch response.statusCode {
        case 200:
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw PlanAPIError.invalidResponse("kein JSON-Objekt")
            }
            guard object["plan_version"] as? Int == Self.planVersion else { throw PlanAPIError.serverOutdated }
            do {
                return try PlanResponse.jsonDecoder().decode(Response.self, from: data)
            } catch {
                throw PlanAPIError.invalidResponse(String(describing: error))
            }
        case 400:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw PlanAPIError.invalidRequest(details: body?.details?.map { "\($0.path): \($0.message)" } ?? [])
        case 404:
            throw PlanAPIError.serverOutdated
        case 503:
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw PlanAPIError.planUnavailable(reason: body?.reason)
        default:
            throw statusError(response.statusCode)
        }
    }

    private struct DayBody: Encodable {
        let planVersion: Int
        let snapshot: AthleteStateSnapshot
        /// Fehlt im JSON, wenn `nil`: Der Server nimmt dann seinen Cache.
        let regenerate: Bool?
        let wishes: String?
        let dayPlan: DayTargetV2?
        let equipment: [String]?
        let recentTraining: [RecentTrainingEntry]?
        let testSettings: TestSettings?
    }

    private struct WeekBody: Encodable {
        let planVersion: Int
        let snapshot: AthleteStateSnapshot
        let fromDate: String
        let today: String
        let unavailableDates: [String]
        let recentTraining: [RecentTrainingEntry]
        let macroWeeks: [MacroWeekV2]?
        let wishes: String?
        let equipment: [String]?
        let testSettings: TestSettings?
    }

    private struct MacroBody: Encodable {
        let planVersion: Int
        let snapshot: AthleteStateSnapshot
        let today: String
        let testSettings: TestSettings?
    }

    private struct ReviewBody: Encodable {
        struct Week: Encodable {
            struct Sport: Encodable {
                let sport: SportID
                let amount: Double
                let sessions: Int
            }

            let weekStart: String
            let sports: [Sport]
        }

        struct Pause: Encodable {
            let from: String
            let to: String?
            let kind: String
        }

        struct Change: Encodable {
            let sport: SportID?
            let metric: String
            let previous: Double?
            let value: Double
            let source: String
            let measuredAt: Date
        }

        let planVersion: Int
        let snapshot: AthleteStateSnapshot
        let today: String
        let plan: ReviseBody.Plan
        let actual: [Week]
        let reason: String
        let pause: Pause?
        let feedback: String?
        let performanceChanges: [Change]?
        let testSettings: TestSettings?
    }

    private struct ReviseBody: Encodable {
        struct Plan: Encodable {
            let rationale: String
            let weeks: [MacroWeekV2]
        }

        struct Round: Encodable {
            let feedback: String
            let changes: [String]
        }

        let planVersion: Int
        let snapshot: AthleteStateSnapshot
        let today: String
        let plan: Plan
        let feedback: String
        let history: [Round]?
        let testSettings: TestSettings?
    }
}
