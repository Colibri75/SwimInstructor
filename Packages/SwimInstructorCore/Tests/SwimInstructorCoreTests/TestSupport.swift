import Foundation
@testable import SwimInstructorCore

/// Gemeinsame Test-Helfer für die M6-Tests (API-Client, Snapshot-Builder, Heute-Bildschirm).
enum TestFixtures {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Nur Schwimmen, Rad und Laufen. Für Tests, deren Ergebnis von der Liste aller Sportarten abhängt: Sie bleiben grün,
    /// wenn die App eine weitere Sportart bekommt (docs/neue-sportart.md).
    static let triathlon = try! SportRegistry(modules: [SwimModule(), BikeModule(), RunModule()])

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

/// Antwortet der Reihe nach mit den angegebenen Antworten (die letzte wiederholt sich).
final class SequenceTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let responses: [(Int, Data)]

    init(_ responses: [(Int, String)]) {
        self.responses = responses.map { ($0.0, Data($0.1.utf8)) }
    }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        _requests.append(request)
        let (status, data) = responses[min(_requests.count, responses.count) - 1]
        lock.unlock()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
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

/// Liefert Einheiten aller Sportarten, wie `HealthKitWorkoutRepository`.
final class FakeAllSportsRepository: WorkoutRepository {
    var workouts: [Workout]
    var error: Error?
    private(set) var requestedStart: Date?

    init(workouts: [Workout] = [], error: Error? = nil) {
        self.workouts = workouts
        self.error = error
    }

    func fetchWorkouts(from startDate: Date) async throws -> [Workout] {
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

/// Tageshöchstwerte des Pulses und Alter wie aus Health.
final class FakePerformanceRepository: PerformanceDataRepository {
    var dailyMaximumHeartRates: [Double]
    var ageInYears: Int?
    var error: Error?
    private(set) var requestedStart: Date?

    init(dailyMaximumHeartRates: [Double] = [], age: Int? = nil, error: Error? = nil) {
        self.dailyMaximumHeartRates = dailyMaximumHeartRates
        self.ageInYears = age
        self.error = error
    }

    func fetchDailyMaximumHeartRates(from startDate: Date) async throws -> [Double] {
        requestedStart = startDate
        if let error { throw error }
        return dailyMaximumHeartRates
    }

    func age(now: Date) -> Int? {
        ageInYears
    }
}

extension TestFixtures {
    /// Eine Einheit irgendeiner Sportart, um 8 Uhr.
    static func workout(
        _ sport: SportID, daysAgo: Int, minutes: Double, meters: Double? = nil, heartRate: Double? = nil
    ) -> Workout {
        let start = date(daysAgo: daysAgo, hour: 8)
        return Workout(
            id: UUID(), sport: sport, startDate: start, endDate: start.addingTimeInterval(minutes * 60),
            duration: minutes * 60, distanceMeters: meters, averageHeartRate: heartRate
        )
    }

    /// Ein Leistungswert mit Datum `daysAgo` Tage vor `now`.
    static func performance(
        _ metric: PerformanceMetric, _ value: Double, _ source: PerformanceOrigin, sport: SportID? = nil, daysAgo: Int = 0
    ) -> PerformanceValue {
        PerformanceValue(sport: sport, metric: metric, value: value, source: source, measuredAt: date(daysAgo: daysAgo, hour: 12))
    }
}
