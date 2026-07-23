import CoreLocation
import Foundation
import MapKit

struct AirportObservation: Identifiable, Codable, Hashable, Sendable {
    let stationID: String
    let stationName: String
    let latitude: Double
    let longitude: Double
    let observedAt: Date
    let windSpeedKnots: Double?
    let windDirectionDegrees: Double?
    let gustKnots: Double?
    let visibilityMiles: Double?
    let temperatureCelsius: Double?
    let dewpointCelsius: Double?
    let altimeterHPA: Double?
    let rawReport: String?

    var id: String { stationID }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var isStale: Bool { Date().timeIntervalSince(observedAt) > 2 * 60 * 60 }
}

struct AirportObservationSnapshot: Sendable {
    let observations: [AirportObservation]
    let fetchedAt: Date
    let isStale: Bool
}

enum AirportWeatherError: Error {
    case invalidResponse
    case noContent
}

actor AirportWeatherProvider {
    private struct METARRecord: Decodable {
        let icaoId: String
        let name: String?
        let lat: Double?
        let lon: Double?
        let reportTime: String?
        let obsTime: Int?
        let wspd: Double?
        let wdir: Double?
        let wgst: Double?
        let visib: String?
        let temp: Double?
        let dewp: Double?
        let altim: Double?
        let rawOb: String?

        enum CodingKeys: String, CodingKey {
            case icaoId, name, lat, lon, reportTime, obsTime, wspd, wdir, wgst, visib, temp, dewp, altim, rawOb
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            icaoId = try container.decode(String.self, forKey: .icaoId)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            lat = container.lossyDouble(forKey: .lat)
            lon = container.lossyDouble(forKey: .lon)
            reportTime = try container.decodeIfPresent(String.self, forKey: .reportTime)
            obsTime = try container.decodeIfPresent(Int.self, forKey: .obsTime)
            wspd = container.lossyDouble(forKey: .wspd)
            wdir = container.lossyDouble(forKey: .wdir)
            wgst = container.lossyDouble(forKey: .wgst)
            visib = try? container.decode(String.self, forKey: .visib)
            temp = container.lossyDouble(forKey: .temp)
            dewp = container.lossyDouble(forKey: .dewp)
            altim = container.lossyDouble(forKey: .altim)
            rawOb = try container.decodeIfPresent(String.self, forKey: .rawOb)
        }
    }

    private let session: URLSession
    private var cached: AirportObservationSnapshot?
    private static let cacheLifetime: TimeInterval = 60

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(in region: MKCoordinateRegion) async throws -> AirportObservationSnapshot {
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            return filtered(cached, in: region)
        }

        var components = URLComponents(string: "https://aviationweather.gov/api/data/metar")!
        let box = GeoMath.expandedBoundingBox(region, factor: 1.25)
        components.queryItems = [
            URLQueryItem(name: "bbox", value: "\(box.south),\(box.west),\(box.north),\(box.east)"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "hours", value: "2")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("SeaSignal/1.0 iOS; airport observations", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AirportWeatherError.invalidResponse }
            if http.statusCode == 204 { throw AirportWeatherError.noContent }
            guard (200..<300).contains(http.statusCode) else { throw AirportWeatherError.invalidResponse }
            let observations = try Self.decode(data)
            let snapshot = AirportObservationSnapshot(observations: observations, fetchedAt: Date(), isStale: false)
            cached = snapshot
            return filtered(snapshot, in: region)
        } catch {
            if let cached {
                return filtered(
                    AirportObservationSnapshot(
                        observations: cached.observations,
                        fetchedAt: cached.fetchedAt,
                        isStale: true
                    ),
                    in: region
                )
            }
            throw error
        }
    }

    static func decode(_ data: Data) throws -> [AirportObservation] {
        let decoder = JSONDecoder()
        let records = try decoder.decode([METARRecord].self, from: data)
        let observations = records.compactMap { record -> AirportObservation? in
            guard let latitude = record.lat, let longitude = record.lon else { return nil }
            let observedAt: Date
            if let seconds = record.obsTime {
                observedAt = Date(timeIntervalSince1970: TimeInterval(seconds))
            } else if let reportTime = record.reportTime,
                      let parsed = ISO8601DateFormatter().date(from: reportTime) {
                observedAt = parsed
            } else {
                return nil
            }
            return AirportObservation(
                stationID: record.icaoId,
                stationName: record.name ?? record.icaoId,
                latitude: latitude,
                longitude: longitude,
                observedAt: observedAt,
                windSpeedKnots: record.wspd,
                windDirectionDegrees: record.wdir,
                gustKnots: record.wgst,
                visibilityMiles: record.visib.flatMap {
                    Double($0.trimmingCharacters(in: CharacterSet(charactersIn: "+")))
                },
                temperatureCelsius: record.temp,
                dewpointCelsius: record.dewp,
                altimeterHPA: record.altim,
                rawReport: record.rawOb
            )
        }
        return Dictionary(grouping: observations, by: \.stationID)
            .compactMap { $0.value.max(by: { $0.observedAt < $1.observedAt }) }
    }

    private func filtered(
        _ snapshot: AirportObservationSnapshot,
        in region: MKCoordinateRegion
    ) -> AirportObservationSnapshot {
        let expanded = GeoMath.expandedRegion(region, factor: 1.25)
        let observations = snapshot.observations
            .filter { GeoMath.contains(expanded, coordinate: $0.coordinate) }
            .sorted {
                GeoMath.distance($0.coordinate, region.center) < GeoMath.distance($1.coordinate, region.center)
            }
            .prefix(24)
        return AirportObservationSnapshot(
            observations: Array(observations),
            fetchedAt: snapshot.fetchedAt,
            isStale: snapshot.isStale
        )
    }
}

private extension KeyedDecodingContainer {
    func lossyDouble(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }
}
