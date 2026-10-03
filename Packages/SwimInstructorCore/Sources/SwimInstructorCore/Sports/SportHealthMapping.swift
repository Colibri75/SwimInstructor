import Foundation
import HealthKit

/// Ein Messwert aus Health, den ein Sport-Modul für seine Einheiten braucht (Strecke, Züge, Watt ...).
///
/// Kennung und Einheit stehen als Text, damit Module `Sendable` bleiben und auch Kennungen nennen können, die
/// erst neuere Systeme kennen (etwa Rad-Watt ab iOS 17): Fehlt der Typ zur Laufzeit, liefert `quantityType`
/// `nil` und der Wert bleibt einfach leer.
public struct HealthQuantity: Equatable, Sendable {
    public enum Aggregation: Equatable, Sendable {
        /// Summe über die Einheit (Strecke, Züge, Energie).
        case sum
        /// Mittelwert über die Einheit (Puls, Watt, Trittfrequenz).
        case average
    }

    /// Rohwert eines `HKQuantityTypeIdentifier`.
    public let identifier: String
    /// Einheit im HealthKit-Format, z. B. "m", "count", "W", "count/min".
    public let unit: String
    public let aggregation: Aggregation

    public init(identifier: String, unit: String, aggregation: Aggregation) {
        self.identifier = identifier
        self.unit = unit
        self.aggregation = aggregation
    }

    public init(_ identifier: HKQuantityTypeIdentifier, unit: String, aggregation: Aggregation) {
        self.init(identifier: identifier.rawValue, unit: unit, aggregation: aggregation)
    }

    public var quantityType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: identifier))
    }

    public var healthUnit: HKUnit {
        HKUnit(from: unit)
    }
}

/// Wie eine Sportart in Health aussieht: welche Workout-Arten zu ihr gehören und welche Messwerte sie liest.
/// Werte, die jedes Workout mitbringen kann (Puls, Energie, Runden, Höhenmeter), liest das Repository für alle
/// Sportarten selbst; hier steht nur, was sportartspezifisch ist.
public struct SportHealthMapping: Sendable {
    /// Rohwerte von `HKWorkoutActivityType` (die Aufzählung selbst ist nicht überall `Sendable`).
    public let activityTypeRawValues: [UInt]
    /// Die Strecke in Metern; `nil` für Sportarten ohne Strecke.
    public let distance: HealthQuantity?
    /// Weitere Messwerte dieser Sportart.
    public let metrics: [WorkoutMetric: HealthQuantity]

    public init(
        activityTypes: [HKWorkoutActivityType],
        distance: HealthQuantity?,
        metrics: [WorkoutMetric: HealthQuantity] = [:]
    ) {
        self.activityTypeRawValues = activityTypes.map(\.rawValue)
        self.distance = distance
        self.metrics = metrics
    }

    public var activityTypes: [HKWorkoutActivityType] {
        activityTypeRawValues.compactMap(HKWorkoutActivityType.init(rawValue:))
    }

    /// Alle Messwerte, die gelesen werden müssen (Strecke zuerst).
    public var quantities: [HealthQuantity] {
        (distance.map { [$0] } ?? []) + metrics.values.sorted { $0.identifier < $1.identifier }
    }

    /// Was die App für diese Sportart in Health lesen darf.
    public var readTypes: Set<HKObjectType> {
        Set(quantities.compactMap { $0.quantityType as HKObjectType? })
    }
}
