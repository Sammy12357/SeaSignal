import Foundation
import CoreLocation

enum ForecastServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case noForecastData

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The forecast URL could not be created."
        case .invalidResponse: "The forecast provider returned an invalid response."
        case .httpStatus(let status): "The forecast provider returned HTTP \(status)."
        case .noForecastData: "No forecast is available for this location."
        }
    }
}

protocol WeatherService: Sendable {
    func windForecast(at coordinate: CLLocationCoordinate2D) async throws -> [WindSample]
}

protocol MarineService: Sendable {
    func marineForecast(at coordinate: CLLocationCoordinate2D) async throws -> [MarineSample]
}

private struct OpenMeteoWeatherResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let windSpeed: [Double]
        let windDirection: [Double]
        let windGusts: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m"
            case windGusts = "wind_gusts_10m"
        }
    }
    let hourly: Hourly
}

private struct OpenMeteoMarineResponse: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let waveHeight: [Double?]?
        let waveDirection: [Double?]?
        let wavePeriod: [Double?]?
        let currentVelocity: [Double?]?
        let currentDirection: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case waveHeight = "wave_height"
            case waveDirection = "wave_direction"
            case wavePeriod = "wave_period"
            case currentVelocity = "ocean_current_velocity"
            case currentDirection = "ocean_current_direction"
        }
    }
    let hourly: Hourly
}

private enum ForecastDateParser {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()
}

final class OpenMeteoWeatherService: WeatherService, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func windForecast(at coordinate: CLLocationCoordinate2D) async throws -> [WindSample] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "forecast_days", value: "3")
        ]
        guard let url = components?.url else { throw ForecastServiceError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw ForecastServiceError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ForecastServiceError.httpStatus(response.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoWeatherResponse.self, from: data)
        let count = min(
            decoded.hourly.time.count,
            decoded.hourly.windSpeed.count,
            decoded.hourly.windDirection.count,
            decoded.hourly.windGusts.count
        )
        let samples = (0..<count).compactMap { index -> WindSample? in
            guard let date = ForecastDateParser.formatter.date(from: decoded.hourly.time[index]) else {
                return nil
            }
            return WindSample(
                coordinate: coordinate,
                timestamp: date,
                speedKPH: decoded.hourly.windSpeed[index],
                directionFromDegrees: decoded.hourly.windDirection[index],
                gustKPH: decoded.hourly.windGusts[index]
            )
        }
        guard !samples.isEmpty else { throw ForecastServiceError.noForecastData }
        return samples
    }
}

final class OpenMeteoMarineService: MarineService, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func marineForecast(at coordinate: CLLocationCoordinate2D) async throws -> [MarineSample] {
        var components = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(
                name: "hourly",
                value: "wave_height,wave_direction,wave_period,ocean_current_velocity,ocean_current_direction"
            ),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "forecast_days", value: "3")
        ]
        guard let url = components?.url else { throw ForecastServiceError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw ForecastServiceError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ForecastServiceError.httpStatus(response.statusCode)
        }
        let decoded = try JSONDecoder().decode(OpenMeteoMarineResponse.self, from: data)
        return decoded.hourly.time.enumerated().compactMap { index, value in
            guard let date = ForecastDateParser.formatter.date(from: value) else { return nil }
            return MarineSample(
                timestamp: date,
                waveHeightMeters: decoded.hourly.waveHeight?[safe: index] ?? nil,
                waveDirectionDegrees: decoded.hourly.waveDirection?[safe: index] ?? nil,
                wavePeriodSeconds: decoded.hourly.wavePeriod?[safe: index] ?? nil,
                currentVelocityKPH: decoded.hourly.currentVelocity?[safe: index] ?? nil,
                currentDirectionDegrees: decoded.hourly.currentDirection?[safe: index] ?? nil
            )
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

actor ForecastCache {
    struct Entry {
        let samples: [WindSample]
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = 30 * 60) {
        self.lifetime = lifetime
    }

    func samples(for coordinate: CLLocationCoordinate2D, allowStale: Bool = false) -> [WindSample]? {
        let key = cacheKey(for: coordinate)
        guard let entry = entries[key] else { return nil }
        if allowStale || Date().timeIntervalSince(entry.storedAt) < lifetime {
            return entry.samples
        }
        return nil
    }

    func store(_ samples: [WindSample], for coordinate: CLLocationCoordinate2D) {
        entries[cacheKey(for: coordinate)] = Entry(samples: samples, storedAt: Date())
    }

    private func cacheKey(for coordinate: CLLocationCoordinate2D) -> String {
        "\(String(format: "%.3f", coordinate.latitude)),\(String(format: "%.3f", coordinate.longitude))"
    }
}

struct SampleWeatherService: WeatherService {
    func windForecast(at coordinate: CLLocationCoordinate2D) async throws -> [WindSample] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(bySetting: .minute, value: 0, of: Date()) ?? Date()
        return (0..<48).compactMap { hour in
            guard let timestamp = calendar.date(byAdding: .hour, value: hour, to: start) else { return nil }
            let locationOffset = abs(coordinate.longitude * 7 + coordinate.latitude * 11)
            return WindSample(
                coordinate: coordinate,
                timestamp: timestamp,
                speedKPH: 10 + sin(Double(hour) / 5 + locationOffset) * 6,
                directionFromDegrees: (225 + Double(hour) * 4 + locationOffset * 8).truncatingRemainder(dividingBy: 360),
                gustKPH: 17 + sin(Double(hour) / 4) * 7
            )
        }
    }
}
