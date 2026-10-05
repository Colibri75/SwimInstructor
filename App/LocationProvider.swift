import CoreLocation
import SwimInstructorCore

/// Der ungefähre Ort für die Wettervorhersage. Fragt nur, wenn "Wetter berücksichtigen" an ist, mit reduzierter Genauigkeit,
/// und merkt sich den letzten Ort auf eine Nachkommastelle gerundet (etwa 10 km). Genauer verlässt er das Gerät nie.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var point: GeoPoint?
    @Published private(set) var isDenied = false

    private static let storageKey = "settings.weatherLocation"
    private let manager = CLLocationManager()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        if let data = defaults.data(forKey: Self.storageKey), let stored = try? JSONDecoder().decode(GeoPoint.self, from: data) {
            point = stored
        }
    }

    /// Fragt einmal nach dem Ort (beim ersten Mal nach der Erlaubnis). Das Ergebnis kommt später in `point`.
    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isDenied = false
            manager.requestLocation()
        default:
            isDenied = true
        }
    }

    /// Wetter aus: den gemerkten Ort vergessen.
    func forget() {
        point = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let rounded = GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        Task { @MainActor in
            self.point = rounded
            if let data = try? JSONEncoder().encode(rounded) {
                self.defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Kein Ort: Der Plan entsteht ohne Wetter, der gemerkte Ort bleibt.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.isDenied = false
                self.manager.requestLocation()
            case .denied, .restricted:
                self.isDenied = true
            default:
                break
            }
        }
    }
}
