import Foundation

struct ForecastService: Sendable {
    private let weather = OpenMeteoWeatherProvider()
    private let marine = OpenMeteoMarineProvider()
    private let engine = RecommendationEngine()

    func result(for launch: BoatLaunch, preferences: AppPreferences) async throws -> RecommendationResult {
        async let weatherResult = weather.fetch(latitude: launch.latitude, longitude: launch.longitude)
        async let marineResult = try? await marine.fetch(latitude: launch.latitude, longitude: launch.longitude)
        async let tideResult = try? await NOAATideProvider.shared.fetch(
            latitude: launch.latitude,
            longitude: launch.longitude,
            preferredStationID: launch.tideStationID
        )
        let (weatherData, marineData, tideData) = try await (weatherResult, marineResult, tideResult)
        let timeline = ForecastTimelineBuilder.build(weather: weatherData, marine: marineData, tides: tideData)
        return RecommendationResult(
            recommendations: engine.recommendations(for: timeline, preferences: preferences),
            timeline: timeline
        )
    }
}
