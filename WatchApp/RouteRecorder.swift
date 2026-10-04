import CoreLocation
import HealthKit
import SwimInstructorCore

/// Zeichnet draußen die GPS-Strecke einer Einheit auf: für die Karte in Health und die Höhenmeter. Läuft nur, solange die
/// Workout-Sitzung läuft; die hält die App auch mit dunklem Bildschirm wach.
@MainActor
final class RouteRecorder: NSObject {
    /// Ungenauere Punkte (Häuserschlucht, Wasser) fallen weg.
    static let maximumHorizontalAccuracy = 50.0

    /// Bekommt die Höhenmeter bergauf nach jedem neuen Punkt.
    var onElevationGain: ((Double) -> Void)?

    private let manager = CLLocationManager()
    private let routeBuilder: HKWorkoutRouteBuilder
    private var elevation = ElevationGainTracker()
    private var hasLocations = false

    init(healthStore: HKHealthStore) {
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// Hängt die Strecke an das gespeicherte Workout. Ohne Punkte (kein GPS, keine Erlaubnis) passiert nichts.
    func finish(with workout: HKWorkout) async {
        stop()
        guard hasLocations else { return }
        _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
    }

    private func receive(_ locations: [CLLocation]) {
        let usable = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= Self.maximumHorizontalAccuracy }
        guard !usable.isEmpty else { return }
        for location in usable {
            elevation.record(altitude: location.altitude, verticalAccuracy: location.verticalAccuracy)
        }
        onElevationGain?(elevation.gainMeters)
        hasLocations = true
        let builder = routeBuilder
        Task { try? await builder.insertRouteData(usable) }
    }
}

extension RouteRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.receive(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Kein GPS: Die Einheit läuft ohne Karte weiter, Strecke und Pace kommen dann aus den Sensoren der Uhr.
    }
}
