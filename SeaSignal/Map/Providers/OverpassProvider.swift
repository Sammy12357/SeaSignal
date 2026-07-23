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

struct OverpassProvider: Sendable {
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    func fetch(in region: MKCoordinateRegion) async throws -> [MapSpot] {
        if let cached = await MapDiskCache.shared.spotValue(for: region) { return cached }

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("SeaSignal/1.0 (iOS boating conditions app)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = Self.formBody(for: region)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let spots = try Self.decode(data)
            await MapDiskCache.shared.store(spots: spots, for: region)
            return spots
        } catch {
            if let stale = await MapDiskCache.shared.staleSpots(for: region) { return stale }
            let fallback = try await mapKitFallback(in: region)
            await MapDiskCache.shared.store(spots: fallback, for: region)
            return fallback
        }
    }

    static func decode(_ data: Data) throws -> [MapSpot] {
        let response = try JSONDecoder().decode(OverpassResponse.self, from: data)
        let spots = response.elements.compactMap { element -> MapSpot? in
            let latitude = element.lat ?? element.center?.lat
            let longitude = element.lon ?? element.center?.lon
            guard let latitude, let longitude else { return nil }

            let isRamp = element.tags?["leisure"] == "slipway"
                || element.tags?["service"] == "slipway"
                || element.tags?["waterway"] == "access_point"
                || element.tags?["amenity"] == "boat_ramp"
            let isPier = element.tags?["man_made"] == "pier"
            guard isRamp || isPier else { return nil }
            let kind: SpotKind = isRamp ? .ramp : .pier
            let fallback = kind == .ramp ? "Public boat ramp" : "Fishing pier"
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

    static func deduplicate(_ spots: [MapSpot], thresholdMetres: Double = 35) -> [MapSpot] {
        var result: [MapSpot] = []
        for spot in spots {
            if let index = result.firstIndex(where: { GeoMath.distance($0.coordinate, spot.coordinate) < thresholdMetres }) {
                let existingIsGeneric = result[index].name == "Public boat ramp" || result[index].name == "Fishing pier"
                let incomingIsNamed = spot.name != "Public boat ramp" && spot.name != "Fishing pier"
                if existingIsGeneric && incomingIsNamed { result[index] = spot }
            } else {
                result.append(spot)
            }
        }
        return result
    }

    private static func formBody(for region: MKCoordinateRegion) -> Data {
        let box = GeoMath.boundingBox(region)
        let bounds = "\(box.south),\(box.west),\(box.north),\(box.east)"
        let query = """
        [out:json][timeout:20];
        (
          nwr["leisure"="slipway"](\(bounds));
          nwr["service"="slipway"](\(bounds));
          nwr["waterway"="access_point"](\(bounds));
          nwr["amenity"="boat_ramp"](\(bounds));
          nwr["man_made"="pier"](\(bounds));
        );
        out center 300;
        """
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "data", value: query)]
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func mapKitFallback(in region: MKCoordinateRegion) async throws -> [MapSpot] {
        await withTaskGroup(of: [MapSpot].self) { group in
            for (query, kind) in [
                ("boat ramp", SpotKind.ramp),
                ("public boat launch", .ramp),
                ("boat landing", .ramp),
                ("kayak launch", .ramp),
                ("marina boat launch", .ramp),
                ("fishing pier", .pier)
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
                        guard let name, !name.isEmpty else { return nil }
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
            return Self.deduplicate(values, thresholdMetres: 75)
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
