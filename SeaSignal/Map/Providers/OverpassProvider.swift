import Foundation
import MapKit

enum RampSearchResultFilter {
    /// Map search can interpret "boat ramp" as any boating-related business. These terms
    /// identify commercial results rather than physical public launch locations. Explicitly
    /// mapped OSM slipways are not passed through this name-only fallback filter.
    private static let excludedPhrases = [
        "rental", "rentals", "jet ski", "boat dealer", "boat sales",
        "boat repair", "boat tour", "boat tours", "boat charter", "boat charters"
    ]

    static func isLikelyLaunch(name: String) -> Bool {
        let normalized = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return !excludedPhrases.contains { normalized.contains($0) }
    }
}

struct OverpassResponse: Decodable {
    let elements: [Element]

    struct Element: Decodable {
        let type: String
        let id: Int64
        let lat: Double?
        let lon: Double?
        let center: Center?
        let tags: [String: String]?

        struct Center: Decodable {
            let lat: Double
            let lon: Double
        }
    }
}

/// Result of a spot lookup. `wasTruncated` is true when Overpass returned exactly the
/// element cap, meaning the area holds more ramps than were returned and the set shown
/// is only part of the picture.
struct SpotFetchResult: Sendable {
    let spots: [MapSpot]
    let wasTruncated: Bool
}

struct OverpassProvider: Sendable {
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    /// Maximum elements Overpass will return for one query. Overpass does not guarantee
    /// *which* elements it returns when it truncates, so hitting this cap must be surfaced
    /// rather than silently displayed.
    static let elementLimit = 600

    func fetch(in region: MKCoordinateRegion) async throws -> SpotFetchResult {
        // Quantise before doing anything else: the tile drives the query, the cache key and
        // the fallbacks, so a small pan or zoom reuses all three.
        let tile = GeoMath.fetchTile(for: region)

        if let cached = await MapDiskCache.shared.spotValue(for: tile) {
            return SpotFetchResult(spots: cached, wasTruncated: cached.count >= Self.elementLimit)
        }

        // MapKit is a permitted supplementary source for the Apple map. Run it alongside
        // OSM rather than only after an OSM failure: either catalog can contain a launch the
        // other does not, and the shared 1,000-foot pass collapses overlap deterministically.
        async let supplementarySpots = mapKitSearch(in: tile)

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 8
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("SeaSignal/1.0 (iOS boating conditions app)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = Self.formBody(for: tile)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let osmSpots = try Self.decode(data)
            let spots = Self.deduplicate(osmSpots + (await supplementarySpots))
            await MapDiskCache.shared.store(spots: spots, for: tile)
            return SpotFetchResult(spots: spots, wasTruncated: osmSpots.count >= Self.elementLimit)
        } catch {
            if let stale = await MapDiskCache.shared.staleSpots(for: tile) {
                return SpotFetchResult(
                    spots: Self.deduplicate(stale + (await supplementarySpots)),
                    wasTruncated: false
                )
            }
            let fallback = await supplementarySpots
            await MapDiskCache.shared.store(spots: fallback, for: tile)
            return SpotFetchResult(spots: fallback, wasTruncated: false)
        }
    }

    static func decode(_ data: Data) throws -> [MapSpot] {
        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)
        let spots = response.elements.compactMap { element -> MapSpot? in
            let latitude = element.lat ?? element.center?.lat
            let longitude = element.lon ?? element.center?.lon
            guard let latitude, let longitude else { return nil }

            // Piers are deliberately not ingested. The OSM `man_made=pier` tag also covers
            // ferry terminals, breakwaters, jetties and walking piers, so it produced large
            // numbers of markers that are neither piers in the angling sense nor launches.
            let isRamp = element.tags?["leisure"] == "slipway"
                || element.tags?["service"] == "slipway"
                || element.tags?["waterway"] == "access_point"
                || element.tags?["amenity"] == "boat_ramp"
                || element.tags?["canoe"] == "put_in"
                || element.tags?["canoe"] == "put_in;egress"
                || element.tags?["whitewater"] == "put_in"
                || element.tags?["whitewater"] == "put_in;egress"
            guard isRamp else { return nil }
            let kind: SpotKind = .ramp
            let fallback = "Public boat ramp"
            let name = element.tags?["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return MapSpot(
                id: "osm:\(element.type):\(element.id)",
                name: name?.isEmpty == false ? name! : fallback,
                latitude: latitude,
                longitude: longitude,
                kind: kind,
                provider: "OpenStreetMap",
                details: Self.details(from: element.tags)
            )
        }
        return deduplicate(spots)
    }

    /// Cheap pre-pass to shrink the payload before it reaches the view model.
    /// Shares the radius and precedence rules with `SpotDeduplicator` so that
    /// provider-level and display-level results can never disagree.
    static func deduplicate(
        _ spots: [MapSpot],
        thresholdMetres: Double = SpotDeduplicator.radiusMetres
    ) -> [MapSpot] {
        SpotDeduplicator.deduplicate(spots, radiusMetres: thresholdMetres)
    }

    private static func formBody(for region: MKCoordinateRegion) -> Data {
        let box = GeoMath.boundingBox(region)
        let bounds = "\(box.south),\(box.west),\(box.north),\(box.east)"
        let query = """
        [out:json][timeout:12];
        (
          nwr["leisure"="slipway"](\(bounds));
          nwr["service"="slipway"](\(bounds));
          nwr["waterway"="access_point"](\(bounds));
          nwr["amenity"="boat_ramp"](\(bounds));
          nwr["canoe"="put_in"](\(bounds));
          nwr["canoe"="put_in;egress"](\(bounds));
          nwr["whitewater"="put_in"](\(bounds));
          nwr["whitewater"="put_in;egress"](\(bounds));
        );
        out center \(Self.elementLimit);
        """
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: query)]
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func mapKitSearch(in region: MKCoordinateRegion) async -> [MapSpot] {
        await withTaskGroup(of: [MapSpot].self) { group in
            // Three distinct queries only. The previous six were near-synonyms that
            // returned the same POIs under slightly different names and coordinates,
            // manufacturing duplicates the dedupe then had to clean up. Fewer parallel
            // MKLocalSearch requests also cuts latency on this failure path.
            for (query, kind) in [
                ("boat ramp", SpotKind.ramp),
                ("boat launch", .ramp),
                ("kayak launch", .ramp)
            ] {
                group.addTask {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = query
                    request.region = region
                    request.resultTypes = .pointOfInterest
                    guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
                    return response.mapItems.compactMap { item in
                        let coordinate = item.placemark.coordinate
                        guard GeoMath.contains(region, coordinate: coordinate) else { return nil }
                        let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let name, !name.isEmpty, RampSearchResultFilter.isLikelyLaunch(name: name) else {
                            return nil
                        }
                        return MapSpot(
                            id: String(format: "mapkit:%@:%0.5f:%0.5f", kind.rawValue, coordinate.latitude, coordinate.longitude),
                            name: name,
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                            kind: kind,
                            provider: "Apple Maps"
                        )
                    }
                }
            }
            var values: [MapSpot] = []
            for await spots in group { values.append(contentsOf: spots) }
            return Self.deduplicate(values)
        }
    }

    private static func details(from tags: [String: String]?) -> [String: String]? {
        guard let tags else { return nil }
        let keys = ["operator", "access", "fee", "surface", "trailer", "motorboat", "canoe", "parking", "toilets", "opening_hours"]
        let values = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            tags[key].map { (key.replacingOccurrences(of: "_", with: " ").capitalized, $0) }
        })
        return values.isEmpty ? nil : values
    }
}
