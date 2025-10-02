import CoreLocation
import SwiftUI

/// Cross-platform location manager for iOS and watchOS
@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isUpdating: Bool = false

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = locationManager.authorizationStatus
    }

    /// Request location permission and start updating location
    func startUpdating() {
        guard authorizationStatus != .denied && authorizationStatus != .restricted else {
            print("⚠️ Location access denied or restricted")
            return
        }

        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        locationManager.startUpdatingLocation()
        isUpdating = true
    }

    /// Stop updating location
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
        isUpdating = false
    }

    /// Get current location once (useful for activity tracking)
    func requestLocation() {
        guard authorizationStatus != .denied && authorizationStatus != .restricted else {
            print("⚠️ Location access denied or restricted")
            return
        }

        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }

        locationManager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.location = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ Location manager failed: \(error.localizedDescription)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
        }
    }
}
