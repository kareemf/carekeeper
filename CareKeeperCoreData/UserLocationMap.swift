import CoreLocation
import MapKit
import SwiftUI

extension MKCoordinateRegion {
    static func bronxZooLocation() -> CLLocation {
        CLLocation(latitude: 40.850581, longitude: -73.87538)
    }

    func getBinding() -> Binding<MKCoordinateRegion>? {
        return Binding<MKCoordinateRegion>(.constant(self))
    }
}

struct UserLocationMap: View {
    @Binding var location: CLLocation?
    @State var showsUserLocation: Bool = true
    @State var dropPinAtLocation: Bool = false

    var region: Binding<MKCoordinateRegion>? {
        let regionLocation = location ?? MKCoordinateRegion.bronxZooLocation()
        let region = MKCoordinateRegion(
            center: regionLocation.coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )

        return region.getBinding()
    }

    var annotations: [IdentifiablePlace] {
        guard let coordinate = location?.coordinate else { return [] }

        let annotation = IdentifiablePlace(coordinate: coordinate)

        return dropPinAtLocation ? [annotation] : []
    }

    var body: some View {
        if let region = region {
            Map(
                coordinateRegion: region,
                interactionModes: .all,
                showsUserLocation: showsUserLocation,
                userTrackingMode: .constant(.follow),
                annotationItems: annotations
            ) { annotation in
                MapMarker(coordinate: annotation.coordinate)
            }
                .ignoresSafeArea()
        }
    }
}

struct IdentifiablePlace: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.coordinate = coordinate
    }
}

struct UserLocationMap_Previews: PreviewProvider {
    static var previews: some View {
        UserLocationMap(
            location: .constant(MKCoordinateRegion.bronxZooLocation()),
            showsUserLocation: true
        )
    }
}
