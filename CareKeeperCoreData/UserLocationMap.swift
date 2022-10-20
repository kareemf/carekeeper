import CoreLocation
import MapKit
import SwiftUI

extension MKCoordinateRegion {
    
    static func bronxZooRegion() -> MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.850581, longitude:  -73.87538), latitudinalMeters: 5000, longitudinalMeters: 5000)
    }
    
    func getBinding() -> Binding<MKCoordinateRegion>? {
        return Binding<MKCoordinateRegion>(.constant(self))
    }
}

struct UserLocationMap: View {
    @StateObject private var locationController = LocationController.shared
    
    var region: Binding<MKCoordinateRegion>? {
        guard let location = locationController.location else {
            return MKCoordinateRegion.bronxZooRegion().getBinding()
        }
        
        let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        
        return region.getBinding()
    }
    
    var body: some View {
        if let region = region {
            Map(coordinateRegion: region, interactionModes: .all, showsUserLocation: true, userTrackingMode: .constant(.follow))
                .ignoresSafeArea()
        }
    }
}

struct UserLocationMap_Previews: PreviewProvider {
    static var previews: some View {
        UserLocationMap()
    }
}
