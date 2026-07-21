import Foundation

struct AppPreferences: Codable, Hashable, Sendable {
    var maxWindKPH: Double
    var maxGustKPH: Double
    var maxWaveM: Double
    var maxRainProbability: Double
    var highTideWindowMinutes: Double
    var requireHighTide: Bool
    var requireDaylight: Bool
    var tripLengthHours: Int

    static let defaults = AppPreferences(
        maxWindKPH: 24,
        maxGustKPH: 32,
        maxWaveM: 0.8,
        maxRainProbability: 50,
        highTideWindowMinutes: 90,
        requireHighTide: false,
        requireDaylight: true,
        tripLengthHours: 6
    )

    static func load(from defaults: UserDefaults = .standard) -> AppPreferences {
        func storedDouble(_ key: String, fallback: Double) -> Double {
            defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        }

        func storedBool(_ key: String, fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }

        return AppPreferences(
            maxWindKPH: storedDouble("maxWindSpeed", fallback: Self.defaults.maxWindKPH),
            maxGustKPH: storedDouble("maxGustSpeed", fallback: Self.defaults.maxGustKPH),
            maxWaveM: storedDouble("maxWaveHeight", fallback: Self.defaults.maxWaveM),
            maxRainProbability: storedDouble("maxRainProbability", fallback: Self.defaults.maxRainProbability),
            highTideWindowMinutes: storedDouble("highTideWindow", fallback: Self.defaults.highTideWindowMinutes),
            requireHighTide: storedBool("requireHighTide", fallback: Self.defaults.requireHighTide),
            requireDaylight: storedBool("requireDaylight", fallback: Self.defaults.requireDaylight),
            tripLengthHours: max(2, Int(storedDouble("tripLength", fallback: Double(Self.defaults.tripLengthHours)).rounded()))
        )
    }
}

