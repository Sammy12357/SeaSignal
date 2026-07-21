import CoreLocation
import Foundation

actor NOAATideProvider {
    static let shared = NOAATideProvider()

    private struct StationResponse: Decodable { let stations: [StationPayload] }
    private struct StationPayload: Decodable {
        let id: String
        let name: String
        let lat: Double
        let lng: Double

        var model: TideStation {
            TideStation(id: id, name: name, latitude: lat, longitude: lng)
        }
    }
    private struct PredictionResponse: Decodable { let predictions: [PredictionPayload]? }
    private struct PredictionPayload: Decodable {
        let t: String
        let v: String
        let type: String?
    }

    private var stationCache: [TideStation]?

    func fetch(latitude: Double, longitude: Double, preferredStationID: String? = nil) async throws -> TideDataset? {
        let stationList = try await loadStations()
        let preferred = preferredStationID.flatMap { id in stationList.first(where: { $0.id == id }) }
        guard let station = preferred ?? nearest(from: stationList, latitude: latitude, longitude: longitude, maximumDistanceKM: 40) else {
            return nil
        }

        async let events = predictions(station: station, interval: "hilo")
        async let hourly = predictions(station: station, interval: "h")
        let (eventPayload, hourlyPayload) = try await (events, hourly)

        return TideDataset(
            station: station,
            events: eventPayload.compactMap { payload in
                guard let type = payload.type.flatMap(TideEvent.Kind.init(rawValue:)) else { return nil }
                return TideEvent(time: payload.date, heightM: payload.heightM, kind: type)
            },
            hourlyHeights: Dictionary(uniqueKeysWithValues: hourlyPayload.map { ($0.date, $0.heightM) })
        )
    }

    func nearestStation(latitude: Double, longitude: Double, maximumDistanceKM: Double) async throws -> TideStation? {
        let stations = try await loadStations()
        return nearest(from: stations, latitude: latitude, longitude: longitude, maximumDistanceKM: maximumDistanceKM)
    }

    func nearbyStations(latitude: Double, longitude: Double, maximumDistanceKM: Double = 80) async throws -> [TideStation] {
        let stations = try await loadStations()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        return stations
            .filter { distance(from: $0, to: location) <= maximumDistanceKM * 1_000 }
            .sorted { distance(from: $0, to: location) < distance(from: $1, to: location) }
            .prefix(20)
            .map { $0 }
    }

    private struct DatedPrediction {
        let date: Date
        let heightM: Double
        let type: String?
    }

    private func predictions(station: TideStation, interval: String) async throws -> [DatedPrediction] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyyMMdd"
        let start = day.string(from: Date())
        let end = day.string(from: Calendar(identifier: .gregorian).date(byAdding: .day, value: 8, to: Date())!)

        var components = URLComponents(string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
        components.queryItems = [
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "application", value: "SeaSignal"),
            URLQueryItem(name: "begin_date", value: start),
            URLQueryItem(name: "end_date", value: end),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "station", value: station.id),
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "format", value: "json")
        ]
        let response = try await CachedHTTPClient.shared.data(for: components.url!, maxAge: 12 * 60 * 60)
        let payload = try JSONDecoder().decode(PredictionResponse.self, from: response.data).predictions ?? []
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd HH:mm"
        return payload.compactMap { item in
            guard let date = parser.date(from: item.t), let height = Double(item.v) else { return nil }
            return DatedPrediction(date: date, heightM: height, type: item.type)
        }
    }

    private func loadStations() async throws -> [TideStation] {
        if let stationCache { return stationCache }
        let url = URL(string: "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions&units=metric")!
        let response = try await CachedHTTPClient.shared.data(for: url, maxAge: 30 * 24 * 60 * 60)
        let stations = try JSONDecoder().decode(StationResponse.self, from: response.data).stations.map(\.model)
        stationCache = stations
        return stations
    }

    private func nearest(
        from stations: [TideStation],
        latitude: Double,
        longitude: Double,
        maximumDistanceKM: Double
    ) -> TideStation? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let nearest = stations.min(by: {
            distance(from: $0, to: location) < distance(from: $1, to: location)
        }) else { return nil }
        return distance(from: nearest, to: location) <= maximumDistanceKM * 1_000 ? nearest : nil
    }

    private func distance(from station: TideStation, to location: CLLocation) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: station.latitude, longitude: station.longitude))
    }
}
