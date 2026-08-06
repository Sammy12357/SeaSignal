import Foundation
import MapKit

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
    private let floridaRamps = FloridaBoatRampProvider()

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

        // In Florida the statewide government inventory is authoritative and already
        // complete for this product's public-access scope. Do not also hit Overpass after
        // it succeeds: that added latency, duplicate records and visible timeout noise.
        if let official = await officialRamps(in: tile), !official.spots.isEmpty {
            await MapDiskCache.shared.store(spots: official.spots, for: tile)
            return SpotFetchResult(spots: official.spots, wasTruncated: official.wasTruncated)
        }

        // OSM remains the nationwide source and the fallback for an official inventory
        // outage or genuine catalog gap.
        if let osm = try? await fetchOpenStreetMap(in: tile) {
            await MapDiskCache.shared.store(spots: osm.spots, for: tile)
            return osm
        }

        if let stale = await MapDiskCache.shared.staleSpots(for: tile) {
            return SpotFetchResult(spots: stale, wasTruncated: false)
        }
        let fallback = try await mapKitFallback(in: tile)
        await MapDiskCache.shared.store(spots: fallback, for: tile)
        return SpotFetchResult(spots: fallback, wasTruncated: false)
    }

    private func officialRamps(in region: MKCoordinateRegion) async -> FloridaRampFetchResult? {
        guard FloridaBoatRampProvider.covers(region) else { return nil }
        return try? await floridaRamps.fetch(in: region)
    }

    private func fetchOpenStreetMap(in region: MKCoordinateRegion) async throws -> SpotFetchResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("SeaSignal/1.0 (iOS boating conditions app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody(for: region)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let spots = try Self.decode(data)
        return SpotFetchResult(spots: spots, wasTruncated: spots.count >= Self.elementLimit)
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
            let tags = element.tags ?? [:]
            let access = tags["access"]?.lowercased()
            guard access != "private", access != "no" else { return nil }
            let waterAccessIsLaunch = tags["waterway"] == "access_point"
                && [tags["boat"], tags["motorboat"], tags["canoe"]]
                    .compactMap { $0?.lowercased() }
                    .contains { ["yes", "designated", "permissive"].contains($0) }
            let isRamp = tags["leisure"] == "slipway"
                || element.tags?["service"] == "slipway"
                || tags["amenity"] == "boat_ramp"
                || waterAccessIsLaunch
            guard isRamp else { return nil }
            let kind: SpotKind = .ramp
            let fallback = "Public boat ramp"
            let name = tags["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceID = "\(element.type):\(element.id)"
            return MapSpot(
                id: "osm:\(sourceID)",
                name: name?.isEmpty == false ? name! : fallback,
                latitude: latitude,
                longitude: longitude,
                kind: kind,
                provider: "OpenStreetMap",
                details: Self.details(from: element.tags),
                sourceID: sourceID,
                sourceURL: "https://www.openstreetmap.org/\(element.type)/\(element.id)",
                verificationLevel: .communityConfirmed,
                accessType: Self.accessType(from: access),
                operationalStatus: .undetermined,
                facilityType: Self.facilityType(from: tags),
                coordinateType: element.type == "node" ? .physicalRamp : .approximate
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
          nwr["amenity"="boat_ramp"](\(bounds));
          nwr["waterway"="access_point"]["boat"~"^(yes|designated|permissive)$"](\(bounds));
          nwr["waterway"="access_point"]["motorboat"~"^(yes|designated|permissive)$"](\(bounds));
          nwr["waterway"="access_point"]["canoe"~"^(yes|designated|permissive)$"](\(bounds));
        );
        out center \(Self.elementLimit);
        """
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: query)]
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func mapKitFallback(in region: MKCoordinateRegion) async throws -> [MapSpot] {
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
                        guard let name, RampNameClassifier.isLikelyLaunch(name) else { return nil }
                        return MapSpot(
                            id: String(format: "mapkit:%@:%0.5f:%0.5f", kind.rawValue, coordinate.latitude, coordinate.longitude),
                            name: name,
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                            kind: kind,
                            provider: "Apple Maps",
                            verificationLevel: .unverified,
                            accessType: .unknown,
                            operationalStatus: .undetermined,
                            facilityType: query.contains("kayak") ? .paddle : .unknown,
                            coordinateType: .approximate
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

    private static func accessType(from value: String?) -> RampAccessType {
        switch value {
        case "customers", "permit", "destination": .restrictedPublic
        case "yes", "permissive", "designated": .publicAccess
        default: .unknown
        }
    }

    private static func facilityType(from tags: [String: String]) -> RampFacilityType {
        let allowed = ["yes", "designated", "permissive"]
        if let canoe = tags["canoe"]?.lowercased(), allowed.contains(canoe),
           tags["motorboat"].map({ allowed.contains($0.lowercased()) }) != true {
            return .paddle
        }
        return .unknown
    }
}

enum RampNameClassifier {
    private static let excludedPhrases = [
        "boat rental", "jet ski rental", "charter", "boat dealer", "boat repair",
        "boat sales", "yacht club", "cruise", "tiki", "tour"
    ]

    static func isLikelyLaunch(_ name: String) -> Bool {
        let normalized = name.lowercased()
        guard !excludedPhrases.contains(where: normalized.contains) else { return false }
        return ["boat ramp", "boat launch", "public ramp", "public launch", "kayak launch", "canoe launch", "slipway"]
            .contains(where: normalized.contains)
    }
}
