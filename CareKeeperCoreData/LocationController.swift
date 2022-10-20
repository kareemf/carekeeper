import CoreLocation

class LocationController: NSObject, CLLocationManagerDelegate, ObservableObject {
    static let shared = LocationController()
    
    @Published var location: CLLocation?

    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        
        locationManager.delegate = self
    }
    
    func startUpdating() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            print("location update")
            self.location = location
        }
    }
}
