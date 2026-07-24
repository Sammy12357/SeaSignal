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

    /// Snaps a viewport onto a stable tile grid so that small pans and zooms reuse the
    /// same Overpass query and the same cache entry.
    ///
    /// Fetching on the raw viewport caused two bugs. Overpass caps results (`out center N`)
    /// and does not guarantee *which* N it returns, so a slightly different bounding box
    /// produced a different arbitrary subset and pins visibly jumped around. And because
    /// `MapDiskCache` keys on the bounding box, every zoom step was a cache miss and a full
    /// network round trip. Quantising fixes both at once.
    ///
    /// The returned tile is padded to twice the bucket size so panning has headroom; callers
    /// still trim to the visible region with `contains(_:coordinate:)`.
    static func fetchTile(for region: MKCoordinateRegion) -> MKCoordinateRegion {
        let rawSpan = max(region.span.latitudeDelta, region.span.longitudeDelta, 0.001)
        let bucket = pow(2.0, log2(rawSpan).rounded(.up))
        let tile = min(max(bucket, 0.03), 4.0)

        let snappedLatitude = (region.center.latitude / tile).rounded() * tile
        let snappedLongitude = (region.center.longitude / tile).rounded() * tile

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: snappedLatitude, longitude: snappedLongitude),
            span: MKCoordinateSpan(latitudeDelta: tile * 2, longitudeDelta: tile * 2)
        )
    }
}
