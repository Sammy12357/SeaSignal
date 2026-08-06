import Foundation

struct HourlyConditions: Codable, Hashable, Sendable {
    let time: Date
    var windSpeedKPH: Double?
    var windGustKPH: Double?
    var windDirectionDegrees: Double?
    var precipitationProbability: Double?
    var precipitationMM: Double?
    var waveHeightM: Double?
    var wavePeriodSeconds: Double?
    var swellHeightM: Double?
    var tideHeightM: Double?
    var isDaylight: Bool?
    var airTemperatureC: Double? = nil
    var surfacePressureHPa: Double? = nil
    var weatherCode: Int? = nil
    var waveDirectionDegrees: Double? = nil
}

struct TideStation: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
}

struct TideEvent: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case high = "H"
        case low = "L"
    }

    let time: Date
    let heightM: Double
    let kind: Kind
}

struct TideDataset: Codable, Hashable, Sendable {
    let station: TideStation
    let events: [TideEvent]
    let hourlyHeights: [Date: Double]
}

struct ForecastTimeline: Codable, Hashable, Sendable {
    let timezoneIdentifier: String
    let hours: [HourlyConditions]
    let tideEvents: [TideEvent]
    let tideSource: String
    let fetchedAt: Date
    let isStale: Bool
}

struct Recommendation: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let start: Date
    let end: Date
    let score: Double
    let rationale: [String]
    let weakestCondition: String?
}

struct RecommendationResult: Codable, Hashable, Sendable {
    let recommendations: [Recommendation]
    let timeline: ForecastTimeline

    var best: Recommendation? { recommendations.first }
}

