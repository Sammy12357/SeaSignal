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
        let region = location.map {
            MKCoordinateRegion(
                center: $0.coordinate,
                latitudinalMeters: 100_000,
                longitudinalMeters: 100_000
            )
        }
        async let officialAttempt = officialSpots(in: region, enabled: constrainToRegion)

        // Independent MapKit searches run together instead of serially. One failed synonym
        // no longer discards successful results from the other query.
        let items = await withTaskGroup(of: [MKMapItem].self, returning: [MKMapItem].self) { group in
            for query in queries {
                group.addTask {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = query
                    request.resultTypes = .pointOfInterest
                    if constrainToRegion, let region { request.region = region }
                    return (try? await MKLocalSearch(request: request).start().mapItems) ?? []
                }
            }
            var combined: [MKMapItem] = []
            for await result in group { combined.append(contentsOf: result) }
            return combined
        }

        let appleSpots = items.compactMap { item -> MapSpot? in
            let coordinate = item.placemark.coordinate
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  RampNameClassifier.isLikelyLaunch(name) else { return nil }
            let place = [item.placemark.locality, item.placemark.administrativeArea]
                .compactMap { $0 }.joined(separator: ", ")
            return MapSpot(
                id: String(format: "mapkit:ramp:%0.5f:%0.5f", coordinate.latitude, coordinate.longitude),
                name: name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                kind: .ramp,
                provider: "Apple Maps",
                details: place.isEmpty ? nil : ["Address": place],
                verificationLevel: .unverified,
                accessType: .unknown,
                operationalStatus: .undetermined,
                facilityType: .unknown,
                coordinateType: .approximate
            )
        }

        let officialSpots = await officialAttempt

        return SpotDeduplicator.deduplicate(officialSpots + appleSpots).map { spot in
            let coordinate = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
            return BoatLaunch(
                id: "map:\(spot.id)",
                name: spot.name,
                location: spot.details?["Address"] ?? spot.facilityType?.label ?? "Location from \(spot.provider ?? "map data")",
                latitude: spot.latitude,
                longitude: spot.longitude,
                distanceMetres: location?.distance(from: coordinate)
            )
        }
        .sorted {
            switch ($0.distanceMetres, $1.distanceMetres) {
            case let (lhs?, rhs?): lhs < rhs
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    private static func officialSpots(in region: MKCoordinateRegion?, enabled: Bool) async -> [MapSpot] {
        guard enabled, let region, FloridaBoatRampProvider.covers(region) else { return [] }
        return (try? await FloridaBoatRampProvider().fetch(in: region).spots) ?? []
    }
}
