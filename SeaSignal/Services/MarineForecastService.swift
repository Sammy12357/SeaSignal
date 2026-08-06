import Foundation

struct MarineForecast: Sendable {
    let conditions: BoatLaunch.Conditions
    let launchTime: String
    let retrievalTime: String
    let highTide: String
    let lowTide: String
    let tideSource: String
    let windSpeed: Int?
    let gustSpeed: Int?
    let waveHeight: Double?
    let wavePeriod: Double?
    let rainChance: Int?
    let score: Double?
    let rationale: [String]
    let summary: String
    let updatedAt: Date
    let isStale: Bool
    let timeline: ForecastTimeline
}

struct MarineForecastService: Sendable {
    private let service = ForecastService()

    func forecast(for launch: BoatLaunch, preferences: AppPreferences) async throws -> MarineForecast {
        let result = try await service.result(for: launch, preferences: preferences)
        let timeline = result.timeline
        let current = timeline.hours.min(by: {
            abs($0.time.timeIntervalSinceNow) < abs($1.time.timeIntervalSinceNow)
        })
        let recommendation = result.best
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone(identifier: timeline.timezoneIdentifier)
        timeFormatter.dateFormat = "EEE h:mm a"

        let upcomingTides = timeline.tideEvents.filter { $0.time >= Date() }.sorted { $0.time < $1.time }
        let high = upcomingTides.first(where: { $0.kind == .high })
        let low = upcomingTides.first(where: { $0.kind == .low })
        let modeled = modeledTideTimes(from: timeline.hours)
        let highText = high.map { timeFormatter.string(from: $0.time) }
            ?? modeled.high.map { "Modeled · \(timeFormatter.string(from: $0))" }
            ?? "Not available here"
        let lowText = low.map { timeFormatter.string(from: $0.time) }
            ?? modeled.low.map { "Modeled · \(timeFormatter.string(from: $0))" }
            ?? "Not available here"

        guard let recommendation else {
            return MarineForecast(
                conditions: .avoid,
                launchTime: "No safe window",
                retrievalTime: "—",
                highTide: highText,
                lowTide: lowText,
                tideSource: timeline.tideSource,
                windSpeed: current?.windSpeedKPH.map { Int($0.rounded()) },
                gustSpeed: current?.windGustKPH.map { Int($0.rounded()) },
                waveHeight: current?.waveHeightM,
                wavePeriod: current?.wavePeriodSeconds,
                rainChance: current?.precipitationProbability.map { Int($0.rounded()) },
                score: nil,
                rationale: ["No contiguous trip window stays within all of your saved safety limits."],
                summary: "No safe window was found in the seven-day forecast.",
                updatedAt: timeline.fetchedAt,
                isStale: timeline.isStale,
                timeline: timeline
            )
        }

        let condition: BoatLaunch.Conditions = recommendation.score >= 0.68 ? .ideal : .caution
        return MarineForecast(
            conditions: condition,
            launchTime: timeFormatter.string(from: recommendation.start),
            retrievalTime: timeFormatter.string(from: recommendation.end),
            highTide: highText,
            lowTide: lowText,
            tideSource: timeline.tideSource,
            windSpeed: current?.windSpeedKPH.map { Int($0.rounded()) },
            gustSpeed: current?.windGustKPH.map { Int($0.rounded()) },
            waveHeight: current?.waveHeightM,
            wavePeriod: current?.wavePeriodSeconds,
            rainChance: current?.precipitationProbability.map { Int($0.rounded()) },
            score: recommendation.score,
            rationale: recommendation.rationale,
            summary: recommendation.rationale.first ?? "This is the highest-scoring safe window in the next seven days.",
            updatedAt: timeline.fetchedAt,
            isStale: timeline.isStale,
            timeline: timeline
        )
    }

    private func modeledTideTimes(from hours: [HourlyConditions]) -> (high: Date?, low: Date?) {
        let values = hours.compactMap { hour -> (Date, Double)? in
            hour.tideHeightM.map { (hour.time, $0) }
        }
        guard values.count >= 3 else { return (nil, nil) }
        var high: Date?
        var low: Date?
        for index in 1..<(values.count - 1) {
            if high == nil, values[index].1 > values[index - 1].1, values[index].1 >= values[index + 1].1 {
                high = values[index].0
            }
            if low == nil, values[index].1 < values[index - 1].1, values[index].1 <= values[index + 1].1 {
                low = values[index].0
            }
            if high != nil, low != nil { break }
        }
        return (high, low)
    }
}
