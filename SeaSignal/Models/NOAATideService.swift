import CoreLocation
import Foundation

struct TideForecast: Sendable {
    let stationName: String
    let nextHigh: Date?
    let nextLow: Date?
}

actor NOAATideService {
    static let shared = NOAATideService()

    private struct StationResponse: Decodable {
        let stations: [Station]
    }

    private struct Station: Decodable {
        let id: String
        let name: String
        let lat: Double
        let lng: Double
    }

    private struct PredictionResponse: Decodable {
        let predictions: [Prediction]?
    }

    private struct Prediction: Decodable {
        let t: String
        let type: String
    }

    private var stations: [Station]?

    func nextTides(latitude: Double, longitude: Double) async throws -> TideForecast? {
        let stationList = try await loadStations()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let nearest = stationList.min(by: {
            distance(from: $0, to: location) < distance(from: $1, to: location)
        }), distance(from: nearest, to: location) <= 250_000 else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyyMMdd"
        let beginDate = dateFormatter.string(from: Date())

        var components = URLComponents(string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
        components.queryItems = [
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "application", value: "SeaSignal"),
            URLQueryItem(name: "begin_date", value: beginDate),
            URLQueryItem(name: "range", value: "72"),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "station", value: nearest.id),
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "units", value: "metric"),
            URLQueryItem(name: "interval", value: "hilo"),
            URLQueryItem(name: "format", value: "json")
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let predictions = try JSONDecoder().decode(PredictionResponse.self, from: data).predictions ?? []

        let predictionFormatter = DateFormatter()
        predictionFormatter.locale = Locale(identifier: "en_US_POSIX")
        predictionFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        predictionFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dated = predictions.compactMap { prediction -> (Date, String)? in
            guard let date = predictionFormatter.date(from: prediction.t), date >= Date() else { return nil }
            return (date, prediction.type)
        }
        return TideForecast(
            stationName: nearest.name,
            nextHigh: dated.first(where: { $0.1 == "H" })?.0,
            nextLow: dated.first(where: { $0.1 == "L" })?.0
        )
    }

    private func loadStations() async throws -> [Station] {
        if let stations { return stations }
        let url = URL(string: "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions&units=metric")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let loaded = try JSONDecoder().decode(StationResponse.self, from: data).stations
        stations = loaded
        return loaded
    }

    private func distance(from station: Station, to location: CLLocation) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: station.lat, longitude: station.lng))
    }
}

