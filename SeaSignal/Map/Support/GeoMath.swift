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

    static func expandedRegion(_ region: MKCoordinateRegion, factor: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: min(180, region.span.latitudeDelta * max(factor, 1)),
                longitudeDelta: min(360, region.span.longitudeDelta * max(factor, 1))
            )
        )
    }

    static func expandedBoundingBox(
        _ region: MKCoordinateRegion,
        factor: Double
    ) -> (south: Double, west: Double, north: Double, east: Double) {
        boundingBox(expandedRegion(region, factor: factor))
    }

    static func contains(_ region: MKCoordinateRegion, coordinate: CLLocationCoordinate2D) -> Bool {
        let box = boundingBox(region)
        return coordinate.latitude >= box.south && coordinate.latitude <= box.north
            && coordinate.longitude >= box.west && coordinate.longitude <= box.east
    }

    static func zoomedRegion(_ region: MKCoordinateRegion, scale: Double) -> MKCoordinateRegion {
        let safeScale = max(scale, 0.01)
        return MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: min(120, max(0.002, region.span.latitudeDelta * safeScale)),
                longitudeDelta: min(180, max(0.002, region.span.longitudeDelta * safeScale))
            )
        )
    }
}
