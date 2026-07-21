import Foundation
import CoreLocation

struct BoatLaunch: Identifiable, Hashable, Codable {
    enum Conditions: String, Codable {
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
    var conditions: Conditions = .loading
    var launchTime: String = "Checking…"
    var retrievalTime: String = "Checking…"
    var highTide: String = "Checking…"
    var lowTide: String = "Checking…"
    var tideSource: String = "Checking tide source…"
    var windSpeed: Int = 0
    var gustSpeed: Int = 0
    var waveHeight: Double? = nil
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
