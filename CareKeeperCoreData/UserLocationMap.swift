import CoreLocation
import MapKit
import SwiftUI

extension MKCoordinateRegion {
    static func bronxZooLocation() -> CLLocation {
        CLLocation(latitude: 40.850581, longitude:  -73.87538)
    }
    
    func getBinding() -> Binding<MKCoordinateRegion>? {
        return Binding<MKCoordinateRegion>(.constant(self))
    }
}

struct UserLocationMap: View {
    @Binding var location: CLLocation?
    
    var region: Binding<MKCoordinateRegion>? {
        let regionLocation = location ?? MKCoordinateRegion.bronxZooLocation()
        let region = MKCoordinateRegion(center: regionLocation.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        
        return region.getBinding()
    }
    
    var body: some View {
        if let region = region {
            Map(coordinateRegion: region,
                interactionModes: .all,
                showsUserLocation: true,
                userTrackingMode: .constant(.follow)
            )
            .ignoresSafeArea()
        }
    }
}

struct UserLocationMap_Previews: PreviewProvider {
    static var previews: some View {
        UserLocationMap(location: .constant(MKCoordinateRegion.bronxZooLocation()))
    }
}
