import CoreLocation
import MapKit

enum BoatLaunchSearchService {
    static func search(near location: CLLocation) async throws -> [BoatLaunch] {
        try await search(queries: ["boat ramp", "boat launch"], near: location, constrainToRegion: true)
    }

    static func search(query: String, near location: CLLocation?) async throws -> [BoatLaunch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await search(
            queries: ["boat ramps in \(trimmed)", "boat launches in \(trimmed)"],
            near: location,
            constrainToRegion: false
        )
    }

    private static func search(
        queries: [String],
        near location: CLLocation?,
        constrainToRegion: Bool
    ) async throws -> [BoatLaunch] {
        var items: [MKMapItem] = []

        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            if constrainToRegion, let location {
                request.region = MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 100_000,
                    longitudinalMeters: 100_000
                )
            }
            items.append(contentsOf: try await MKLocalSearch(request: request).start().mapItems)
        }

        var seen = Set<String>()
        return items.compactMap { item -> BoatLaunch? in
            let coordinate = item.placemark.coordinate
            let name = item.name ?? "Boat launch"
            let id = String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
            guard seen.insert(id).inserted else { return nil }
            let place = [item.placemark.locality, item.placemark.administrativeArea]
                .compactMap { $0 }.joined(separator: ", ")
            let distance = location?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) ?? 0
            return BoatLaunch(
                id: id,
                name: name,
                location: place.isEmpty ? "Location from Apple Maps" : place,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                distanceMetres: distance
            )
        }
        .sorted { $0.distanceMetres < $1.distanceMetres }
    }
}
