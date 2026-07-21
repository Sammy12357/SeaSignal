import Foundation

struct MarineForecast: Sendable {
    let conditions: BoatLaunch.Conditions
    let launchTime: String
    let retrievalTime: String
    let highTide: String
    let lowTide: String
    let tideSource: String
    let windSpeed: Int
    let gustSpeed: Int
    let waveHeight: Double?
    let summary: String
    let updatedAt: Date
}

struct MarineForecastService: Sendable {
    private struct WeatherResponse: Decodable {
        let timezone: String
        let hourly: WeatherHourly
    }
    private struct WeatherHourly: Decodable {
        let time: [String]
        let wind_speed_10m: [Double?]
        let wind_gusts_10m: [Double?]
    }
    private struct MarineResponse: Decodable {
        let hourly: MarineHourly
    }
    private struct MarineHourly: Decodable {
        let time: [String]
        let wave_height: [Double?]
        let sea_level_height_msl: [Double?]
    }

    func forecast(latitude: Double, longitude: Double, maxWind: Double, maxGust: Double, maxWave: Double) async throws -> MarineForecast {
        let coordinate = "latitude=\(latitude)&longitude=\(longitude)"
        let weatherURL = URL(string: "https://api.open-meteo.com/v1/forecast?\(coordinate)&hourly=wind_speed_10m,wind_gusts_10m&wind_speed_unit=kmh&timezone=auto&forecast_days=3")!
        let marineURL = URL(string: "https://marine-api.open-meteo.com/v1/marine?\(coordinate)&hourly=wave_height,sea_level_height_msl&timezone=auto&forecast_days=3&cell_selection=sea")!

        async let weatherRequest = URLSession.shared.data(from: weatherURL)
        async let marineRequest = URLSession.shared.data(from: marineURL)
        async let officialTides = try? await NOAATideService.shared.nextTides(latitude: latitude, longitude: longitude)
        let ((weatherData, weatherResponse), (marineData, marineResponse), tideForecast) = try await (weatherRequest, marineRequest, officialTides)
        guard (weatherResponse as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let weather = try JSONDecoder().decode(WeatherResponse.self, from: weatherData)
        let marine = (marineResponse as? HTTPURLResponse)?.statusCode == 200
            ? try? JSONDecoder().decode(MarineResponse.self, from: marineData)
            : nil

        let count = weather.hourly.time.count
        guard count > 0 else { throw URLError(.cannotParseResponse) }
        let now = Date()
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
        parser.timeZone = TimeZone(identifier: weather.timezone)
        let dates = weather.hourly.time.map { parser.date(from: $0) }
        let start = dates.firstIndex { ($0 ?? .distantPast) >= now } ?? 0
        let tripHours = max(2, Int(UserDefaults.standard.double(forKey: "tripLength").nonZero(or: 6).rounded()))

        func acceptable(_ index: Int) -> Bool {
            let wind = weather.hourly.wind_speed_10m[safe: index] ?? nil
            let gust = weather.hourly.wind_gusts_10m[safe: index] ?? nil
            let wave = marine?.hourly.wave_height[safe: index] ?? nil
            return (wind ?? .infinity) <= maxWind
                && (gust ?? .infinity) <= maxGust
                && (wave == nil || wave! <= maxWave)
        }

        let windowStart = (start..<max(start, count - tripHours)).first { candidate in
            (candidate...min(candidate + tripHours, count - 1)).allSatisfy(acceptable)
        }
        let currentIndex = min(start, count - 1)
        let wind = weather.hourly.wind_speed_10m[safe: currentIndex] ?? nil
        let gust = weather.hourly.wind_gusts_10m[safe: currentIndex] ?? nil
        let wave = marine?.hourly.wave_height[safe: currentIndex] ?? nil

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        formatter.timeZone = TimeZone(identifier: weather.timezone)
        let levels = marine?.hourly.sea_level_height_msl ?? []
        let modeledHighIndex = nextTideIndex(levels: levels, after: start, high: true)
        let modeledLowIndex = nextTideIndex(levels: levels, after: start, high: false)
        let modeledHigh = modeledHighIndex.flatMap { dates[safe: $0] ?? nil }.map { "Modeled · \(formatter.string(from: $0))" }
        let modeledLow = modeledLowIndex.flatMap { dates[safe: $0] ?? nil }.map { "Modeled · \(formatter.string(from: $0))" }
        let highTide = tideForecast?.nextHigh.map { formatter.string(from: $0) } ?? modeledHigh ?? "Not available here"
        let lowTide = tideForecast?.nextLow.map { formatter.string(from: $0) } ?? modeledLow ?? "Not available here"
        let tideSource = tideForecast.map { "NOAA station: \($0.stationName)" }
            ?? (modeledHigh != nil || modeledLow != nil ? "Modeled water level — not for navigation" : "No tide source available")

        guard let windowStart, let launchDate = dates[windowStart], let retrieveDate = dates[min(windowStart + tripHours, count - 1)] else {
            return MarineForecast(
                conditions: .avoid, launchTime: "No safe window", retrievalTime: "—", highTide: highTide, lowTide: lowTide, tideSource: tideSource,
                windSpeed: Int((wind ?? 0).rounded()), gustSpeed: Int((gust ?? 0).rounded()), waveHeight: wave,
                summary: "No full trip window stays within your saved wind, gust, and wave limits.", updatedAt: now
            )
        }

        let margin = maxWind - (wind ?? maxWind)
        let condition: BoatLaunch.Conditions = margin < 5 ? .caution : .ideal
        return MarineForecast(
            conditions: condition,
            launchTime: formatter.string(from: launchDate),
            retrievalTime: formatter.string(from: retrieveDate),
            highTide: highTide,
            lowTide: lowTide,
            tideSource: tideSource,
            windSpeed: Int((wind ?? 0).rounded()),
            gustSpeed: Int((gust ?? 0).rounded()),
            waveHeight: wave,
            summary: "Live hourly forecast stays within your limits for this suggested window.",
            updatedAt: now
        )
    }

    private func nextTideIndex(levels: [Double?], after start: Int, high: Bool) -> Int? {
        guard levels.count >= 3 else { return nil }
        let lower = max(1, start)
        let upper = min(levels.count - 1, start + 48)
        guard lower < upper else { return nil }
        return (lower..<upper).first { index in
            guard let current = levels[index], let before = levels[index - 1], let after = levels[index + 1] else { return false }
            return high
                ? (current > before && current >= after)
                : (current < before && current <= after)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private extension Double {
    func nonZero(or fallback: Double) -> Double { self == 0 ? fallback : self }
}
