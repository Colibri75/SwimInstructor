import Foundation

/// Der Plan für den Wettkampftag (`POST /v1/plan/race`): Ablauf, Pacing je Disziplin, Wechsel, Verpflegung, Packliste.
public struct RacePlan: Codable, Equatable, Sendable {
    public struct TimelineEntry: Codable, Equatable, Sendable, Identifiable {
        /// Minuten relativ zum Start, negativ davor.
        public let minutesFromStart: Int
        public let title: String
        public let details: String

        public var id: String { "\(minutesFromStart)|\(title)" }

        public init(minutesFromStart: Int, title: String, details: String) {
            self.minutesFromStart = minutesFromStart
            self.title = title
            self.details = details
        }
    }

    public struct Pacing: Codable, Equatable, Sendable {
        public let segment: String
        /// `nil` ohne Ziel oder bei einem Ziel, das diese App-Version nicht kennt.
        public let targetType: StepTarget?
        public let targetValue: Double?
        public let cue: String
        public let instructions: String

        public init(segment: String, targetType: StepTarget?, targetValue: Double?, cue: String, instructions: String) {
            self.segment = segment
            self.targetType = targetType
            self.targetValue = targetValue
            self.cue = cue
            self.instructions = instructions
        }

        private enum CodingKeys: String, CodingKey {
            case segment, targetType, targetValue, cue, instructions
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            segment = try container.decode(String.self, forKey: .segment)
            targetType = try container.decodeIfPresent(String.self, forKey: .targetType).flatMap(StepTarget.init(rawValue:))
            let value = try container.decodeIfPresent(Double.self, forKey: .targetValue)
            targetValue = targetType == nil ? nil : value
            cue = try container.decodeIfPresent(String.self, forKey: .cue) ?? ""
            instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        }

        /// "5:45 /km" oder `nil` ohne Ziel.
        public var targetText: String? { PlanV2Formatting.target(type: targetType, value: targetValue) }
    }

    public struct Discipline: Codable, Equatable, Sendable, Identifiable {
        public let sport: SportID
        public let distanceMeters: Double
        public let targetMinutes: Double
        public let pacing: [Pacing]
        public let notes: String

        public var id: SportID { sport }

        public init(sport: SportID, distanceMeters: Double, targetMinutes: Double, pacing: [Pacing], notes: String) {
            self.sport = sport
            self.distanceMeters = distanceMeters
            self.targetMinutes = targetMinutes
            self.pacing = pacing
            self.notes = notes
        }
    }

    public struct Transition: Codable, Equatable, Sendable, Identifiable {
        public let afterSport: SportID
        public let beforeSport: SportID
        public let checklist: [String]

        public var id: String { "\(afterSport.rawValue)>\(beforeSport.rawValue)" }

        public init(afterSport: SportID, beforeSport: SportID, checklist: [String]) {
            self.afterSport = afterSport
            self.beforeSport = beforeSport
            self.checklist = checklist
        }
    }

    public struct Fuel: Codable, Equatable, Sendable, Identifiable {
        public let sport: SportID
        public let carbsGPerHour: Int
        public let fluidMlPerHour: Int
        public let sodiumMgPerHour: Int
        public let notes: String

        public var id: SportID { sport }

        public init(sport: SportID, carbsGPerHour: Int, fluidMlPerHour: Int, sodiumMgPerHour: Int, notes: String) {
            self.sport = sport
            self.carbsGPerHour = carbsGPerHour
            self.fluidMlPerHour = fluidMlPerHour
            self.sodiumMgPerHour = sodiumMgPerHour
            self.notes = notes
        }

        /// "60 g Kohlenhydrate, 600 ml, 500 mg Natrium pro Stunde".
        public var summary: String {
            "\(carbsGPerHour) g Kohlenhydrate, \(fluidMlPerHour) ml, \(sodiumMgPerHour) mg Natrium pro Stunde"
        }
    }

    public struct Nutrition: Codable, Equatable, Sendable {
        public let before: [String]
        public let during: [Fuel]
        public let after: [String]

        public init(before: [String], during: [Fuel], after: [String]) {
            self.before = before
            self.during = during
            self.after = after
        }
    }

    public let overview: String
    public let timeline: [TimelineEntry]
    public let disciplines: [Discipline]
    public let transitions: [Transition]
    public let nutrition: Nutrition
    public let checklist: [String]
    public let totalMinutes: Double

    public init(
        overview: String,
        timeline: [TimelineEntry],
        disciplines: [Discipline],
        transitions: [Transition],
        nutrition: Nutrition,
        checklist: [String],
        totalMinutes: Double
    ) {
        self.overview = overview
        self.timeline = timeline
        self.disciplines = disciplines
        self.transitions = transitions
        self.nutrition = nutrition
        self.checklist = checklist
        self.totalMinutes = totalMinutes
    }
}

/// Das Wetter am Wettkampftag, wenn der Server schon eine Vorhersage hatte.
public struct RaceWeather: Codable, Equatable, Sendable {
    public let date: String
    public let tempMaxC: Double
    public let tempMinC: Double
    public let precipitationMm: Double
    public let precipitationProbability: Double
    public let windMaxKmh: Double
    public let weatherCode: Int

    /// "15 bis 27 °C, Regen 10 %, Wind bis 15 km/h".
    public var summary: String {
        "\(Int(tempMinC.rounded())) bis \(Int(tempMaxC.rounded())) °C, Regen \(Int(precipitationProbability.rounded())) %, Wind bis \(Int(windMaxKmh.rounded())) km/h"
    }
}

/// Antwort von `POST /v1/plan/race`, so auch auf dem Gerät gespeichert.
public struct RacePlanResponse: Codable, Equatable, Sendable {
    public let planVersion: Int
    public let raceDay: String
    public let generatedAt: Date
    public let plan: RacePlan
    public let adjustments: [String]
    public let weather: RaceWeather?
    /// Nur in der App: die Startzeit und Notizen, mit denen der Plan geholt wurde.
    public var startTime: String?
    public var notes: String?
}

/// Anfrage für den Wettkampftag-Plan.
public struct RacePlanRequest: Equatable, Sendable {
    public static let maxNotesLength = 500

    public var snapshot: AthleteStateSnapshot
    public var today: String
    /// "HH:MM", wenn bekannt.
    public var startTime: String?
    public var location: GeoPoint?
    public var bodyWeightKg: Double?
    public var notes: String?

    public init(snapshot: AthleteStateSnapshot, today: String, startTime: String? = nil, location: GeoPoint? = nil, bodyWeightKg: Double? = nil, notes: String? = nil) {
        self.snapshot = snapshot
        self.today = today
        self.startTime = startTime
        self.location = location
        self.bodyWeightKg = bodyWeightKg
        self.notes = notes
    }
}

public protocol RacePlanProviding: Sendable {
    func fetchRacePlan(_ request: RacePlanRequest) async throws -> RacePlanResponse
}

extension PlanAPIClient: RacePlanProviding {
    public func fetchRacePlan(_ request: RacePlanRequest) async throws -> RacePlanResponse {
        let notes = request.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        var response: RacePlanResponse = try await postV2(path: "v1/plan/race", timeout: Self.macroTimeout, body: RaceBody(
            planVersion: Self.planVersion,
            snapshot: request.snapshot,
            today: request.today,
            startTime: request.startTime,
            location: request.location,
            bodyWeightKg: request.bodyWeightKg,
            notes: (notes?.isEmpty ?? true) ? nil : notes.map { String($0.prefix(RacePlanRequest.maxNotesLength)) }
        ))
        response.startTime = request.startTime
        response.notes = notes
        return response
    }

    private struct RaceBody: Encodable {
        let planVersion: Int
        let snapshot: AthleteStateSnapshot
        let today: String
        let startTime: String?
        let location: GeoPoint?
        let bodyWeightKg: Double?
        let notes: String?
    }
}

public protocol RacePlanStoring {
    func load() -> RacePlanResponse?
    func save(_ response: RacePlanResponse) throws
}

public struct FileRacePlanStore: RacePlanStoring {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func standard() -> FileRacePlanStore {
        FileRacePlanStore(fileURL: PlanV2Files.url("race-plan.json"))
    }

    public func load() -> RacePlanResponse? {
        PlanV2Files.read(RacePlanResponse.self, from: fileURL)
    }

    public func save(_ response: RacePlanResponse) throws {
        try PlanV2Files.write(response, to: fileURL)
    }
}

/// Holt und hält den Wettkampftag-Plan. Absichtlich ohne SwiftUI.
@MainActor
public final class RacePlanLoader: ObservableObject {
    @Published public private(set) var response: RacePlanResponse?
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: String?
    @Published public private(set) var needsConfiguration = false

    private let store: RacePlanStoring
    private let planProvider: @MainActor () -> RacePlanProviding?
    private let now: () -> Date
    private let calendar: Calendar

    public init(store: RacePlanStoring, planProvider: @escaping @MainActor () -> RacePlanProviding?, now: @escaping () -> Date = { Date() }, calendar: Calendar = .current) {
        self.store = store
        self.planProvider = planProvider
        self.now = now
        self.calendar = calendar
        self.response = store.load()
    }

    /// Der gespeicherte Plan gehört zum Zieltag `raceDay`? Nach einem neuen Ziel nicht mehr.
    public func matches(raceDay: String) -> Bool {
        response?.raceDay == raceDay
    }

    @discardableResult
    public func generate(snapshot: AthleteStateSnapshot, startTime: String?, notes: String?, location: GeoPoint?) async -> Bool {
        guard !isLoading else { return false }
        guard let provider = planProvider() else {
            needsConfiguration = true
            return false
        }
        needsConfiguration = false
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await provider.fetchRacePlan(RacePlanRequest(
                snapshot: snapshot,
                today: PlanFormatting.isoDay(now(), calendar: calendar),
                startTime: startTime,
                location: location,
                notes: notes
            ))
            response = fresh
            error = nil
            try? store.save(fresh)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Uhrzeit eines Eintrags im Ablauf bei Start um `startTime` ("HH:MM"), sonst "-90 min" bzw. "+30 min".
    public static func clock(minutesFromStart: Int, startTime: String?) -> String {
        let parts = startTime?.split(separator: ":").compactMap { Int($0) } ?? []
        guard parts.count == 2 else {
            if minutesFromStart == 0 { return "Start" }
            return minutesFromStart < 0 ? "\(minutesFromStart) min" : "+\(minutesFromStart) min"
        }
        let total = ((parts[0] * 60 + parts[1] + minutesFromStart) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
