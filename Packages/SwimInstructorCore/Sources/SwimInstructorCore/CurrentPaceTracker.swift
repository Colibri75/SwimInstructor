import Foundation

/// Die aktuelle Pace während der Einheit, aus den letzten Strecken-Meldungen der Uhr.
///
/// Health meldet die Strecke bahnweise. Die Pace ergibt sich aus der Strecke zwischen der letzten Meldung
/// und einer früheren, höchstens `window` Sekunden zurück (Zeit ohne Pausen der Aufzeichnung, Pausen am
/// Beckenrand also eingerechnet, wie bei der Pace im Rest der App). Liegt die letzte Meldung länger als
/// `staleAfter` zurück (Pause am Beckenrand), gibt es keine aktuelle Pace.
public struct CurrentPaceTracker: Equatable, Sendable {
    /// So weit zurück darf die frühere Meldung liegen.
    public static let window: TimeInterval = 90
    /// So lange gilt die letzte Pace nach der letzten Meldung.
    public static let staleAfter: TimeInterval = 75
    /// Weniger Strecke ergibt keine verlässliche Pace.
    public static let minimumMeters = 20.0

    private struct Sample: Equatable, Sendable {
        let elapsed: TimeInterval
        let distance: Double
    }

    private var samples: [Sample] = []

    public init() {}

    /// Eine neue Stand-Meldung. Nur wenn die Strecke wächst, zählt sie als Meldung.
    public mutating func record(elapsed: TimeInterval, distanceMeters: Double) {
        if samples.isEmpty { samples.append(Sample(elapsed: 0, distance: 0)) }
        guard let last = samples.last, distanceMeters > last.distance, elapsed > last.elapsed else { return }
        samples.append(Sample(elapsed: elapsed, distance: distanceMeters))
        // Nur das Nötige behalten.
        if samples.count > 40 { samples.removeFirst(samples.count - 40) }
    }

    /// Pace in Sekunden pro 100 m zum Zeitpunkt `elapsed`; `nil` ohne verlässliche Werte.
    public func pace(atElapsed elapsed: TimeInterval) -> Double? {
        guard let last = samples.last, samples.count >= 2 else { return nil }
        guard elapsed - last.elapsed <= Self.staleAfter else { return nil }
        // Die früheste Meldung innerhalb des Fensters (vor der letzten), mindestens eine davor.
        let earlier = samples.dropLast().first { last.elapsed - $0.elapsed <= Self.window } ?? samples[samples.count - 2]
        let meters = last.distance - earlier.distance
        let seconds = last.elapsed - earlier.elapsed
        guard meters >= Self.minimumMeters, seconds > 0 else { return nil }
        return seconds / (meters / 100)
    }
}
