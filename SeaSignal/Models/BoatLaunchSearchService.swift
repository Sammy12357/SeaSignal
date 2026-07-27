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
        let items = try await withThrowingTaskGroup(of: [MKMapItem].self) { group in
            for query in queries {
                group.addTask {
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
                    return try await MKLocalSearch(request: request).start().mapItems
                }
            }
            var combined: [MKMapItem] = []
            for try await result in group { combined.append(contentsOf: result) }
            return combined
        }

        let launches = items.compactMap { item -> BoatLaunch? in
            let coordinate = item.placemark.coordinate
            let name = item.name ?? "Boat launch"
            guard RampSearchResultFilter.isLikelyLaunch(name: name) else { return nil }
            let id = String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
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

        var deduplicated: [BoatLaunch] = []
        for launch in launches where !deduplicated.contains(where: {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(
                from: CLLocation(latitude: launch.latitude, longitude: launch.longitude)
            ) < SpotDeduplicator.radiusMetres
        }) {
            deduplicated.append(launch)
        }
        return deduplicated
    }
}
