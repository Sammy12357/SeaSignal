import Foundation

struct WeatherDataset: Sendable {
    let timezoneIdentifier: String
    let hours: [HourlyConditions]
    let fetchedAt: Date
    let isStale: Bool
}

struct MarineDataset: Sendable {
    let timezoneIdentifier: String
    let valuesByTime: [Date: MarineValue]
    let fetchedAt: Date
    let isStale: Bool
}

struct MarineValue: Sendable {
    let waveHeightM: Double?
    let wavePeriodSeconds: Double?
    let swellHeightM: Double?
    let modeledSeaLevelM: Double?
}

struct OpenMeteoWeatherResponse: Decodable {
    let timezone: String
    let hourly: Hourly

    struct Hourly: Decodable {
        let time: [String]
        let wind_speed_10m: [Double?]
        let wind_gusts_10m: [Double?]
        let wind_direction_10m: [Double?]
        let precipitation_probability: [Double?]
        let precipitation: [Double?]
        let is_day: [Int?]
    }
}

struct OpenMeteoMarineResponse: Decodable {
    let timezone: String
    let hourly: Hourly

    struct Hourly: Decodable {
        let time: [String]
        let wave_height: [Double?]
        let wave_period: [Double?]
        let swell_wave_height: [Double?]
        let sea_level_height_msl: [Double?]
    }
}

struct OpenMeteoWeatherProvider: Sendable {
    func fetch(latitude: Double, longitude: Double) async throws -> WeatherDataset {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "wind_speed_10m,wind_gusts_10m,wind_direction_10m,precipitation_probability,precipitation,is_day"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7")
        ]
        let response = try await CachedHTTPClient.shared.data(for: components.url!, maxAge: 3 * 60 * 60)
        let decoded = try JSONDecoder().decode(OpenMeteoWeatherResponse.self, from: response.data)
        let dates = LocalForecastDateParser.parse(decoded.hourly.time, timezoneIdentifier: decoded.timezone)
        let hours = dates.indices.compactMap { index -> HourlyConditions? in
            guard let date = dates[index] else { return nil }
            return HourlyConditions(
                time: date,
                windSpeedKPH: decoded.hourly.wind_speed_10m[safe: index] ?? nil,
                windGustKPH: decoded.hourly.wind_gusts_10m[safe: index] ?? nil,
                windDirectionDegrees: decoded.hourly.wind_direction_10m[safe: index] ?? nil,
                precipitationProbability: decoded.hourly.precipitation_probability[safe: index] ?? nil,
                precipitationMM: decoded.hourly.precipitation[safe: index] ?? nil,
                waveHeightM: nil,
                wavePeriodSeconds: nil,
                swellHeightM: nil,
                tideHeightM: nil,
                isDaylight: (decoded.hourly.is_day[safe: index] ?? nil).map { $0 == 1 }
            )
        }
        return WeatherDataset(
            timezoneIdentifier: decoded.timezone,
            hours: hours,
            fetchedAt: response.fetchedAt,
            isStale: response.isStale
        )
    }
}

struct OpenMeteoMarineProvider: Sendable {
    func fetch(latitude: Double, longitude: Double) async throws -> MarineDataset {
        var components = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "wave_height,wave_period,swell_wave_height,sea_level_height_msl"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "cell_selection", value: "sea")
        ]
        let response = try await CachedHTTPClient.shared.data(for: components.url!, maxAge: 3 * 60 * 60)
        let decoded = try JSONDecoder().decode(OpenMeteoMarineResponse.self, from: response.data)
        let dates = LocalForecastDateParser.parse(decoded.hourly.time, timezoneIdentifier: decoded.timezone)
        var values: [Date: MarineValue] = [:]
        for index in dates.indices {
            guard let date = dates[index] else { continue }
            values[date] = MarineValue(
                waveHeightM: decoded.hourly.wave_height[safe: index] ?? nil,
                wavePeriodSeconds: decoded.hourly.wave_period[safe: index] ?? nil,
                swellHeightM: decoded.hourly.swell_wave_height[safe: index] ?? nil,
                modeledSeaLevelM: decoded.hourly.sea_level_height_msl[safe: index] ?? nil
            )
        }
        return MarineDataset(
            timezoneIdentifier: decoded.timezone,
            valuesByTime: values,
            fetchedAt: response.fetchedAt,
            isStale: response.isStale
        )
    }
}

enum LocalForecastDateParser {
    static func parse(_ values: [String], timezoneIdentifier: String) -> [Date?] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return values.map(formatter.date)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

