import Foundation
import CoreLocation

struct BoatLaunch: Identifiable, Hashable, Codable, Sendable {
    enum Conditions: String, Codable, Sendable {
        case ideal = "Ideal"
        case caution = "Caution"
        case avoid = "Avoid"
        case loading = "Checking"
    }

    let id: String
    let name: String
    let location: String
    let latitude: Double
    let longitude: Double
    var distanceMetres: Double
    var tideStationID: String? = nil
    var tideStationName: String? = nil
    var conditions: Conditions = .loading
    var launchTime: String = "Checking…"
    var retrievalTime: String = "Checking…"
    var highTide: String = "Checking…"
    var lowTide: String = "Checking…"
    var tideSource: String = "Checking tide source…"
    var windSpeed: Int = 0
    var gustSpeed: Int = 0
    var waveHeight: Double? = nil
    var wavePeriod: Double? = nil
    var rainChance: Int? = nil
    var recommendationScore: Double? = nil
    var rationale: [String]? = nil
    var forecastIsStale: Bool? = nil
    var summary: String = "Loading the latest forecast for this location."
    var forecastUpdatedAt: Date? = nil

    var distance: String {
        if distanceMetres < 1_000 { return "\(Int(distanceMetres)) m" }
        return String(format: "%.1f km", distanceMetres / 1_000)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
