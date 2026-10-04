import Foundation
import HealthKit

/// Wo eine Einheit stattfindet und was die Uhr dort aufzeichnet: Becken oder Freiwasser, draußen oder drinnen.
public struct RecordingLocation: Sendable, Equatable, Identifiable {
    /// Kennung wie bei Sportarten, eindeutig innerhalb der Sportart.
    public let id: String
    /// Deutscher Name für die Auswahl, z. B. "Becken".
    public let displayName: String
    public let symbolName: String
    /// `true` drinnen, `false` draußen, `nil` offen lassen (Health entscheidet).
    public let isIndoor: Bool?
    /// Rohwert von `HKWorkoutSwimmingLocationType`, `nil` außer beim Schwimmen.
    public let swimmingLocationRawValue: Int?
    /// Vor dem Start die Bahnlänge wählen; die Uhr zählt dann Bahnen.
    public let usesLapLength: Bool
    /// GPS-Strecke für die Karte in Health aufzeichnen.
    public let recordsRoute: Bool
    /// Wassersperre an, solange die Einheit läuft.
    public let usesWaterLock: Bool

    public init(
        id: String,
        displayName: String,
        symbolName: String,
        isIndoor: Bool?,
        swimmingLocationRawValue: Int? = nil,
        usesLapLength: Bool = false,
        recordsRoute: Bool = false,
        usesWaterLock: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.symbolName = symbolName
        self.isIndoor = isIndoor
        self.swimmingLocationRawValue = swimmingLocationRawValue
        self.usesLapLength = usesLapLength
        self.recordsRoute = recordsRoute
        self.usesWaterLock = usesWaterLock
    }
}

public extension RecordingLocation {
    /// Im Becken: Bahnen zählen, Wassersperre. Ob drinnen oder draußen, lässt die Uhr offen (wie bisher).
    static let pool = RecordingLocation(
        id: "pool", displayName: "Becken", symbolName: "figure.pool.swim", isIndoor: nil,
        swimmingLocationRawValue: HKWorkoutSwimmingLocationType.pool.rawValue, usesLapLength: true, usesWaterLock: true
    )
    /// Im Freiwasser: Strecke und Karte per GPS, Wassersperre.
    static let openWater = RecordingLocation(
        id: "open_water", displayName: "Freiwasser", symbolName: "water.waves", isIndoor: false,
        swimmingLocationRawValue: HKWorkoutSwimmingLocationType.openWater.rawValue, recordsRoute: true, usesWaterLock: true
    )
    /// Draußen: Strecke und Karte per GPS.
    static let outdoor = RecordingLocation(id: "outdoor", displayName: "Draußen", symbolName: "sun.max", isIndoor: false, recordsRoute: true)
    /// Drinnen (Laufband, Rolle): ohne GPS.
    static let indoor = RecordingLocation(id: "indoor", displayName: "Drinnen", symbolName: "house", isIndoor: true)
}

/// Wie die Uhr die aktuelle Geschwindigkeit glättet (siehe `SpeedTracker`).
public struct SpeedSmoothing: Sendable, Equatable {
    public let window: TimeInterval
    public let staleAfter: TimeInterval
    public let minimumMeters: Double

    public init(window: TimeInterval, staleAfter: TimeInterval, minimumMeters: Double) {
        self.window = window
        self.staleAfter = staleAfter
        self.minimumMeters = minimumMeters
    }

    public func makeTracker() -> SpeedTracker {
        SpeedTracker(window: window, staleAfter: staleAfter, minimumMeters: minimumMeters)
    }
}

/// Was ein Sport-Modul der Watch beibringt: Orte zur Auswahl vor dem Start und die Werte der Anzeige.
public struct SportRecording: Sendable, Equatable {
    /// Der erste ist vorausgewählt.
    public let locations: [RecordingLocation]
    /// Groß neben dem Puls.
    public let primaryField: LiveField
    /// Klein darunter, nur wenn es sie gerade gibt (Watt und Trittfrequenz nur mit Sensor).
    public let secondaryFields: [LiveField]
    public let speedSmoothing: SpeedSmoothing

    public init(locations: [RecordingLocation], primaryField: LiveField, secondaryFields: [LiveField], speedSmoothing: SpeedSmoothing) {
        self.locations = locations
        self.primaryField = primaryField
        self.secondaryFields = secondaryFields
        self.speedSmoothing = speedSmoothing
    }

    /// Für Sportarten ohne eigene Angaben: draußen oder drinnen, Tempo in km/h und Strecke.
    public static let standard = SportRecording(
        locations: [.outdoor, .indoor],
        primaryField: .speed,
        secondaryFields: [.distanceKilometers],
        speedSmoothing: SpeedSmoothing(window: 30, staleAfter: 15, minimumMeters: 20)
    )

    /// Der Ort mit dieser Kennung, sonst der erste.
    public func location(id: String?) -> RecordingLocation? {
        locations.first { $0.id == id } ?? locations.first
    }

    /// Mindestens ein Ort, jede Kennung gültig und nur einmal.
    var isValid: Bool {
        var seen = Set<String>()
        return !locations.isEmpty && locations.allSatisfy {
            SportID(rawValue: $0.id).isWellFormed && !$0.displayName.isEmpty && seen.insert($0.id).inserted
        }
    }
}

public extension SportModule {
    /// Wie diese Sportart an einem Ort aufgezeichnet wird.
    func workoutConfiguration(at location: RecordingLocation, lapLengthMeters: Int) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = health.activityTypes.first ?? .other
        if let indoor = location.isIndoor {
            configuration.locationType = indoor ? .indoor : .outdoor
        }
        if let raw = location.swimmingLocationRawValue, let type = HKWorkoutSwimmingLocationType(rawValue: raw) {
            configuration.swimmingLocationType = type
        }
        if location.usesLapLength {
            configuration.lapLength = HKQuantity(unit: .meter(), doubleValue: Double(PoolLength.clamped(lapLengthMeters)))
        }
        return configuration
    }

    /// Metadaten fürs Workout in Health, damit Apples Fitness-App es so führt wie eine Einheit aus der eigenen App
    /// (Becken mit Bahnlänge, Freiwasser, drinnen oder draußen).
    func workoutMetadata(at location: RecordingLocation, lapLengthMeters: Int) -> [String: Any] {
        var metadata: [String: Any] = [:]
        if location.usesLapLength {
            metadata[HKMetadataKeyLapLength] = HKQuantity(unit: .meter(), doubleValue: Double(PoolLength.clamped(lapLengthMeters)))
        }
        if let raw = location.swimmingLocationRawValue {
            metadata[HKMetadataKeySwimmingLocationType] = NSNumber(value: raw)
        }
        if let indoor = location.isIndoor {
            metadata[HKMetadataKeyIndoorWorkout] = NSNumber(value: indoor)
        }
        return metadata
    }

    /// Bahnlänge für Fortschritt und Auswertung: im Becken die gewählte, sonst `nil`.
    func lapLength(at location: RecordingLocation, lapLengthMeters: Int) -> Int? {
        location.usesLapLength ? PoolLength.clamped(lapLengthMeters) : nil
    }
}

public extension SportRegistry {
    /// Was die Watch in Health schreibt: Workout, Strecke für die Karte, Puls, Energie und die Messwerte aller Sportarten.
    var workoutShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for identifier in [HKQuantityTypeIdentifier.heartRate, .activeEnergyBurned] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) }
        }
        for module in modules {
            for quantity in module.health.quantities {
                if let type = quantity.quantityType { types.insert(type) }
            }
        }
        return types
    }
}
