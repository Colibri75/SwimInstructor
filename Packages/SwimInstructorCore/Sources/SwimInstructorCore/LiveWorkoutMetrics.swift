import Foundation

/// Werte einer laufenden Einheit auf der Watch, für jede Sportart und unabhängig von HealthKit-Typen.
public struct LiveWorkoutMetrics: Equatable, Sendable {
    public var elapsed: TimeInterval
    public var distanceMeters: Double
    /// Bahnen im Becken (aus den Runden-Ereignissen der Uhr), sonst 0.
    public var laps: Int
    public var heartRate: Double?
    public var activeEnergyKilocalories: Double
    public var elevationGainMeters: Double
    /// Aktuelle Geschwindigkeit in m/s aus den letzten Metern (`SpeedTracker`), `nil` ohne verlässlichen Wert.
    public var currentSpeed: Double?
    /// Was nur manche Sportarten messen (Züge, Watt, Trittfrequenz): Summen als Summe, sonst der letzte Wert.
    public var values: [WorkoutMetric: Double]

    public init(
        elapsed: TimeInterval = 0,
        distanceMeters: Double = 0,
        laps: Int = 0,
        heartRate: Double? = nil,
        activeEnergyKilocalories: Double = 0,
        elevationGainMeters: Double = 0,
        currentSpeed: Double? = nil,
        values: [WorkoutMetric: Double] = [:]
    ) {
        self.elapsed = elapsed
        self.distanceMeters = distanceMeters
        self.laps = laps
        self.heartRate = heartRate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.elevationGainMeters = elevationGainMeters
        self.currentSpeed = currentSpeed
        self.values = values
    }

    public static let zero = LiveWorkoutMetrics()

    /// Schnitt über die ganze Einheit in m/s, Pausen am Beckenrand oder an der Ampel eingerechnet.
    public var averageSpeed: Double? {
        guard distanceMeters > 0, elapsed > 0 else { return nil }
        return distanceMeters / elapsed
    }

    /// Strecke für den Stand im Plan. Mit Bahnlänge zählen mindestens die Bahnen mal Bahnlänge, falls die Strecke aus
    /// Health verspätet oder gar nicht kommt (wie `LiveSwimMetrics.progressMeters`).
    public func progressMeters(lapLengthMeters: Int?) -> Double {
        guard let lapLengthMeters, lapLengthMeters > 0 else { return distanceMeters }
        return max(distanceMeters, Double(laps * lapLengthMeters))
    }
}

/// Ein Wert, den die Watch während der Einheit zeigen kann. Welche sie zeigt, bestimmt das Sport-Modul
/// (`SportRecording`).
public enum LiveField: String, Sendable, CaseIterable {
    /// Aktuelle Pace pro 100 m.
    case pacePerHundredMeters
    /// Aktuelle Pace pro km.
    case pacePerKilometer
    /// Aktuelles Tempo in km/h.
    case speed
    case distanceMeters
    case distanceKilometers
    case laps
    case strokes
    case power
    case cadence
    case elevationGain
}

/// Texte der Live-Werte für die Watch. `nil` heißt: Den Wert gibt es gerade nicht (keine Pace in der Pause, keine Watt
/// ohne Leistungsmesser), die Watch lässt ihn weg.
public enum LiveFieldFormatting {
    /// Der Wert ohne Einheit, groß darstellbar: "1:52", "5:10", "28,4", "1.250", "5,23", "18", "245".
    public static func value(_ field: LiveField, metrics: LiveWorkoutMetrics) -> String? {
        switch field {
        case .pacePerHundredMeters:
            return pace(speed: metrics.currentSpeed, per: 100)
        case .pacePerKilometer:
            return pace(speed: metrics.currentSpeed, per: 1000)
        case .speed:
            return metrics.currentSpeed.flatMap(speedText)
        case .distanceMeters:
            return PlanFormatting.meters(Int(metrics.distanceMeters)).replacingOccurrences(of: " m", with: "")
        case .distanceKilometers:
            return decimal(metrics.distanceMeters / 1000, digits: 2)
        case .laps:
            return metrics.laps > 0 ? "\(metrics.laps)" : nil
        case .strokes:
            return positive(metrics.values[.strokes])
        case .power:
            return positive(metrics.values[.averagePower])
        case .cadence:
            return positive(metrics.values[.averageCadence])
        case .elevationGain:
            return positive(metrics.elevationGainMeters)
        }
    }

    /// Die Einheit zum Wert: "/100 m", "/km", "km/h", "m", "km", "Bahnen", "Züge", "W", "U/min", "Hm".
    public static func unit(_ field: LiveField) -> String {
        switch field {
        case .pacePerHundredMeters: return "/100 m"
        case .pacePerKilometer: return "/km"
        case .speed: return "km/h"
        case .distanceMeters: return "m"
        case .distanceKilometers: return "km"
        case .laps: return String(localized: "Bahnen")
        case .strokes: return String(localized: "Züge")
        case .power: return "W"
        case .cadence: return String(localized: "U/min")
        case .elevationGain: return String(localized: "Hm", comment: "Höhenmeter")
        }
    }

    /// Wert und Einheit: "1:52 /100 m", "245 W"; `nil` wie bei `value`.
    public static func text(_ field: LiveField, metrics: LiveWorkoutMetrics) -> String? {
        value(field, metrics: metrics).map { "\($0) \(unit(field))" }
    }

    /// Schnitt der ganzen Einheit für die Zusammenfassung, im Format des Hauptwerts: "2:05 /100 m", "5:40 /km", "26,1 km/h".
    public static func average(_ field: LiveField, metrics: LiveWorkoutMetrics) -> String? {
        var average = metrics
        average.currentSpeed = metrics.averageSpeed
        switch field {
        case .pacePerHundredMeters, .pacePerKilometer, .speed:
            return text(field, metrics: average)
        default:
            return nil
        }
    }

    /// Unter 0,2 m/s (langsamer als 8:20 pro 100 m oder 83 min pro km) gibt es keine sinnvolle Pace.
    private static func pace(speed: Double?, per meters: Double) -> String? {
        guard let speed, speed >= 0.2, speed.isFinite else { return nil }
        return PlanFormatting.pace(meters / speed)
    }

    private static func speedText(_ speed: Double) -> String? {
        guard speed > 0, speed.isFinite else { return nil }
        return decimal(speed * 3.6, digits: 1)
    }

    private static func positive(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0.5 else { return nil }
        return "\(Int(value.rounded()))"
    }

    private static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: AppLocale.current, value)
    }
}

/// Die aktuelle Geschwindigkeit aus den letzten Streckenmeldungen, wie `CurrentPaceTracker`, aber mit einem Fenster je
/// Sportart: Beim Schwimmen kommt die Strecke bahnweise, beim Laufen und Radfahren alle paar Sekunden.
public struct SpeedTracker: Equatable, Sendable {
    /// So weit zurück darf die frühere Meldung liegen.
    public let window: TimeInterval
    /// So lange gilt die letzte Geschwindigkeit nach der letzten Meldung.
    public let staleAfter: TimeInterval
    /// Weniger Strecke ergibt keinen verlässlichen Wert.
    public let minimumMeters: Double

    private var samples: [TimedValue] = []

    public init(window: TimeInterval, staleAfter: TimeInterval, minimumMeters: Double) {
        self.window = window
        self.staleAfter = staleAfter
        self.minimumMeters = minimumMeters
    }

    /// Eine neue Meldung. Nur wenn die Strecke wächst, zählt sie.
    public mutating func record(elapsed: TimeInterval, distanceMeters: Double) {
        if samples.isEmpty { samples.append(TimedValue(elapsed: 0, value: 0)) }
        guard let last = samples.last, distanceMeters > last.value, elapsed > last.elapsed else { return }
        samples.append(TimedValue(elapsed: elapsed, value: distanceMeters))
        // Nur das Fenster und eine Meldung davor behalten.
        while samples.count > 2, elapsed - samples[1].elapsed > window {
            samples.removeFirst()
        }
    }

    /// Geschwindigkeit in m/s zur Laufzeit `elapsed`; `nil` ohne verlässliche Werte oder nach einer Weile ohne Meldung.
    public func speed(atElapsed elapsed: TimeInterval) -> Double? {
        guard let last = samples.last, samples.count >= 2 else { return nil }
        guard elapsed - last.elapsed <= staleAfter else { return nil }
        let earlier = samples.dropLast().first { last.elapsed - $0.elapsed <= window } ?? samples[samples.count - 2]
        let meters = last.value - earlier.value
        let seconds = last.elapsed - earlier.elapsed
        guard meters >= minimumMeters, seconds > 0 else { return nil }
        return meters / seconds
    }
}

/// Höhenmeter bergauf aus den Höhen der GPS-Punkte. Schwankungen unter `threshold` zählen nicht: Die Höhe springt auch
/// auf flacher Strecke um ein paar Meter.
public struct ElevationGainTracker: Equatable, Sendable {
    public static let threshold = 3.0
    /// Ungenauere Höhen fallen weg.
    public static let maximumVerticalAccuracy = 20.0

    public private(set) var gainMeters = 0.0
    private var reference: Double?

    public init() {}

    /// Eine neue Höhe. `verticalAccuracy` wie bei `CLLocation`: negativ heißt ungültig.
    public mutating func record(altitude: Double, verticalAccuracy: Double) {
        guard altitude.isFinite, verticalAccuracy >= 0, verticalAccuracy <= Self.maximumVerticalAccuracy else { return }
        guard let reference else {
            self.reference = altitude
            return
        }
        if altitude - reference >= Self.threshold {
            gainMeters += altitude - reference
            self.reference = altitude
        } else if reference - altitude >= Self.threshold {
            self.reference = altitude
        }
    }
}
