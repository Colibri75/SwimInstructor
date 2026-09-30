import Foundation
@testable import SwimInstructorCore

/// Gemeinsame Test-Helfer für die M6-Tests (API-Client, Snapshot-Builder, Heute-Bildschirm).
enum TestFixtures {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 30.09.2026, 12:00 UTC, wie in den M3-Tests.
    static let now = utc.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!

    static func date(daysAgo: Int, hour: Int) -> Date {
        let midnight = utc.startOfDay(for: now)
        return utc.date(byAdding: .day, value: -daysAgo, to: midnight)!.addingTimeInterval(TimeInterval(hour * 3600))
    }

    static func workout(daysAgo: Int, meters: Double?, seconds: TimeInterval = 1800, hour: Int = 10) -> SwimWorkout {
        let start = date(daysAgo: daysAgo, hour: hour)
        return SwimWorkout(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(seconds),
            duration: seconds,
            totalDistanceMeters: meters,
            lapCount: nil,
            totalStrokeCount: nil,
            averageHeartRate: nil
        )
    }

    static let snapshot = AthleteStateCalculator(calendar: utc).snapshot(
        workouts: [workout(daysAgo: 1, meters: 1500)],
        now: now
    )

    static let responseJSON = """
    {
      "source": "claude",
      "date": "2026-09-30",
      "generated_at": "2026-09-30T10:00:00.000Z",
      "stale": false,
      "adjustments": ["Umfang von 4000 m auf 2400 m gekürzt (Grenze für heute: 2400 m)"],
      "plan": {
        "session_type": "endurance",
        "intensity": "moderate",
        "rationale": "Gute Erholung, maßvoll steigern.",
        "total_distance_meters": 1600,
        "estimated_duration_minutes": 45,
        "sets": [
          {
            "name": "Einschwimmen",
            "repetitions": 1,
            "distance_meters": 400,
            "target_pace_seconds_per_hundred_meters": null,
            "rest_seconds": 0,
            "instructions": "locker"
          },
          {
            "name": "Hauptsatz",
            "repetitions": 6,
            "distance_meters": 200,
            "target_pace_seconds_per_hundred_meters": 140,
            "rest_seconds": 30,
            "instructions": "gleichmäßig"
          }
        ],
        "coach_notes": ["Auf lockere Atmung achten."]
      }
    }
    """

    static func response(date: String = "2026-09-30", source: PlanSource = .claude, stale: Bool = false) -> PlanResponse {
        PlanResponse(
            source: source,
            date: date,
            generatedAt: now,
            stale: stale,
            plan: TrainingPlan(
                sessionType: .technique,
                intensity: .easy,
                rationale: "Test",
                totalDistanceMeters: 800,
                estimatedDurationMinutes: 25,
                sets: [PlanSet(name: "Technik", repetitions: 8, distanceMeters: 100, targetPaceSecondsPerHundredMeters: nil, restSeconds: 20, instructions: "Abschlag")],
                coachNotes: []
            ),
            adjustments: [],
            fallbackReason: source == .fallback ? "timeout" : nil
        )
    }
}

/// Nimmt Anfragen entgegen und antwortet mit einer festen Antwort oder einem Fehler.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let result: Result<(Int, Data), Error>

    init(status: Int, body: String) {
        result = .success((status, Data(body.utf8)))
    }

    init(error: Error) {
        result = .failure(error)
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
        let (status, data) = try result.get()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

final class FakeWorkoutRepository: SwimWorkoutRepository {
    var workouts: [SwimWorkout]
    var error: Error?
    private(set) var requestedStart: Date?

    init(workouts: [SwimWorkout] = [], error: Error? = nil) {
        self.workouts = workouts
        self.error = error
    }

    func fetchRecentSwimWorkouts(limit: Int) async throws -> [SwimWorkout] {
        if let error { throw error }
        return Array(workouts.prefix(limit))
    }

    func fetchSwimWorkouts(from startDate: Date) async throws -> [SwimWorkout] {
        requestedStart = startDate
        if let error { throw error }
        return workouts.filter { $0.startDate >= startDate }
    }
}

final class FakeVitalsRepository: DailyVitalsRepository {
    var vitals: [DailyVitals]
    var error: Error?
    private(set) var requestedStart: Date?

    init(vitals: [DailyVitals] = [], error: Error? = nil) {
        self.vitals = vitals
        self.error = error
    }

    func fetchDailyVitals(from startDate: Date) async throws -> [DailyVitals] {
        requestedStart = startDate
        if let error { throw error }
        return vitals
    }
}

struct TestError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
