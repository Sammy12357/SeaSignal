import CoreLocation
import MapKit

enum GeoMath {
    static func distance(_ first: CLLocationCoordinate2D, _ second: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
    }

    static func boundingBox(_ region: MKCoordinateRegion) -> (south: Double, west: Double, north: Double, east: Double) {
        let halfLatitude = region.span.latitudeDelta / 2
        let halfLongitude = region.span.longitudeDelta / 2
        return (
            region.center.latitude - halfLatitude,
            region.center.longitude - halfLongitude,
            region.center.latitude + halfLatitude,
            region.center.longitude + halfLongitude
        )
    }

    static func contains(_ region: MKCoordinateRegion, coordinate: CLLocationCoordinate2D) -> Bool {
        let box = boundingBox(region)
        return coordinate.latitude >= box.south && coordinate.latitude <= box.north
            && coordinate.longitude >= box.west && coordinate.longitude <= box.east
    }
}
