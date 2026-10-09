import Foundation
import HealthKit

public protocol WorkoutSplitRepository: Sendable {
    /// Ereignisse, Strecke und Züge einer Einheit; leer, wenn Health die Einheit nicht (mehr) kennt.
    func splitData(for workout: Workout) async throws -> WorkoutSplitData
}

/// Liest Bahnen, Sets und die einzelnen Streckenmessungen einer Einheit aus Health. Strecke und Züge nur, wenn sie mit
/// dem Workout verknüpft sind, sonst würden iPhone und Watch doppelt zählen.
public final class HealthKitWorkoutSplitRepository: WorkoutSplitRepository, @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let registry: SportRegistry

    public init(healthStore: HKHealthStore = HKHealthStore(), registry: SportRegistry = .standard) {
        self.healthStore = healthStore
        self.registry = registry
    }

    public func splitData(for workout: Workout) async throws -> WorkoutSplitData {
        guard let healthWorkout = try await healthWorkout(id: workout.id) else { return WorkoutSplitData() }
        let module = registry.module(for: workout.sport)
        var data = Self.data(from: healthWorkout)
        if let type = module?.health.distance?.quantityType, let unit = module?.health.distance?.healthUnit {
            data.distance = try await samples(type, unit: unit, of: healthWorkout)
        }
        if let strokes = module?.health.metrics[.strokes], let type = strokes.quantityType {
            data.strokes = try await samples(type, unit: strokes.healthUnit, of: healthWorkout)
        }
        return data
    }

    /// Was im Workout selbst steht: Ereignisse und Beckenlänge.
    static func data(from workout: HKWorkout) -> WorkoutSplitData {
        var lapLength: Double?
        if let quantity = workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity, quantity.is(compatibleWith: .meter()) {
            lapLength = quantity.doubleValue(for: .meter())
        }
        return WorkoutSplitData(events: events(from: workout.workoutEvents ?? []), lapLengthMeters: lapLength)
    }

    static func events(from events: [HKWorkoutEvent]) -> [WorkoutEventInterval] {
        events.compactMap { event in
            let kind: WorkoutEventInterval.Kind
            switch event.type {
            case .lap: kind = .lap
            case .segment: kind = .segment
            case .pause, .motionPaused: kind = .pause
            case .resume, .motionResumed: kind = .resume
            default: return nil
            }
            let style = (event.metadata?[HKMetadataKeySwimmingStrokeStyle] as? NSNumber)
                .flatMap { SwimStrokeStyle(rawValue: $0.intValue) }
            return WorkoutEventInterval(kind: kind, start: event.dateInterval.start, end: event.dateInterval.end, strokeStyle: style)
        }
    }

    private func healthWorkout(id: UUID) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: HKQuery.predicateForObject(with: id),
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    if HealthKitSwimWorkoutRepository.isNoData(error) {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout])?.first)
            }
            healthStore.execute(query)
        }
    }

    private func samples(_ type: HKQuantityType, unit: HKUnit, of workout: HKWorkout) async throws -> [WorkoutQuantitySample] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if HealthKitSwimWorkoutRepository.isNoData(error) {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let values = (samples as? [HKQuantitySample] ?? []).map {
                    WorkoutQuantitySample(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }
}

/// Texte für Sets, Bahnen und Teilstrecken im Workout-Detail.
public enum WorkoutSplitFormatting {
    /// "0:28", "3:45", "1:02:10".
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Schwimmen in Metern ("200 m"), sonst ab 1 km in Kilometern ("1,00 km").
    public static func distance(_ meters: Double, field: LiveField) -> String {
        if field == .pacePerHundredMeters || meters < 1000 {
            return "\(decimal(meters, digits: 0)) m"
        }
        return "\(decimal(meters / 1000, digits: 2)) km"
    }

    /// "1:52 /100 m", "5:12 /km" oder "28,4 km/h", passend zum Hauptfeld der Sportart.
    public static func speed(_ metersPerSecond: Double?, field: LiveField) -> String? {
        guard let metersPerSecond, metersPerSecond.isFinite, metersPerSecond > 0 else { return nil }
        switch field {
        case .pacePerHundredMeters:
            return "\(duration(100 / metersPerSecond)) /100 m"
        case .speed:
            return "\(decimal(metersPerSecond * 3.6, digits: 1)) km/h"
        default:
            return "\(duration(1000 / metersPerSecond)) /km"
        }
    }

    /// Zweite Zeile einer Zeile: "200 m · 1:52 /100 m · Freistil · 142 bpm".
    public static func detail(_ split: WorkoutSplit, field: LiveField, includeDistance: Bool = true) -> String {
        var parts: [String] = []
        if includeDistance, let meters = split.distanceMeters, meters > 0 {
            parts.append(distance(meters, field: field))
        }
        if let speed = speed(split.speed, field: field) { parts.append(speed) }
        if let style = split.strokeStyle { parts.append(style.displayName) }
        if let strokes = split.strokes, strokes > 0 {
            let count = Int(strokes.rounded())
            parts.append(String(localized: "\(count) Züge"))
        }
        if let heartRate = split.averageHeartRate { parts.append("\(Int(heartRate.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }

    public static func setsTitle(field: LiveField) -> String {
        field == .pacePerHundredMeters ? String(localized: "Sets") : String(localized: "Abschnitte")
    }

    public static func setTitle(_ number: Int, field: LiveField) -> String {
        field == .pacePerHundredMeters ? String(localized: "Set \(number)") : String(localized: "Abschnitt \(number)")
    }

    public static func lapsTitle(field: LiveField) -> String {
        field == .pacePerHundredMeters ? String(localized: "Bahnen") : String(localized: "Runden")
    }

    public static func lapTitle(_ number: Int, field: LiveField) -> String {
        field == .pacePerHundredMeters ? String(localized: "Bahn \(number)") : String(localized: "Runde \(number)")
    }

    /// "Kilometer" oder "Teilstrecken je 5 km".
    public static func splitsTitle(length: Double) -> String {
        guard length != 1000 else { return String(localized: "Kilometer") }
        let kilometers = decimal(length / 1000, digits: 0)
        return String(localized: "Teilstrecken je \(kilometers) km")
    }

    /// "Kilometer 3" oder "km 10–15"; der Rest am Ende mit seiner echten Länge ("km 85–87,3").
    public static func splitTitle(_ split: WorkoutSplit, length: Double) -> String {
        if length == 1000, split.distanceMeters.map({ abs($0 - length) < 0.5 }) ?? true {
            return String(localized: "Kilometer \(split.number)")
        }
        let from = Double(split.number - 1) * length / 1000
        let to = from + (split.distanceMeters ?? length) / 1000
        let toDigits = abs(to - to.rounded()) < 0.05 ? 0 : 1
        return "km \(decimal(from, digits: 0))–\(decimal(to, digits: toDigits))"
    }

    /// "Pause 0:30".
    public static func rest(_ seconds: TimeInterval) -> String {
        let time = duration(seconds)
        return String(localized: "Pause \(time)")
    }

    private static func decimal(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocale.current
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
