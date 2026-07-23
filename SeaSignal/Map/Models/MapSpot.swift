import CoreLocation
import Foundation

enum SpotKind: String, Codable, Hashable, Sendable, CaseIterable {
    case ramp
    case pier
    case weatherSpot

    var glyph: String {
        switch self {
        case .ramp: "ferry.fill"
        case .pier: "figure.fishing"
        case .weatherSpot: "cloud.sun.fill"
        }
    }

    var label: String {
        switch self {
        case .ramp: "Boat ramp"
        case .pier: "Fishing pier"
        case .weatherSpot: "Weather spot"
        }
    }
}

struct MapSpot: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let kind: SpotKind
    let provider: String?
    let details: [String: String]?

    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        kind: SpotKind,
        provider: String? = nil,
        details: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
        self.provider = provider
        self.details = details
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum MapDisplayItem: Identifiable, Hashable {
    case spot(MapSpot)
    case cluster(id: String, latitude: Double, longitude: Double, count: Int)

    var id: String {
        switch self {
        case .spot(let spot): spot.id
        case .cluster(let id, _, _, _): id
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .spot(let spot): spot.coordinate
        case .cluster(_, let latitude, let longitude, _):
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

enum SpotFilter: String, CaseIterable, Identifiable {
    case all
    case ramps
    case piers
    case weatherSpots
    case marineStations
    case airports

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .ramps: "Boat ramps"
        case .piers: "Piers"
        case .weatherSpots: "Weather spots"
        case .marineStations: "Marine stations"
        case .airports: "Airports"
        }
    }

    func matches(_ spot: MapSpot) -> Bool {
        switch self {
        case .all: true
        case .ramps: spot.kind == .ramp
        case .piers: spot.kind == .pier
        case .weatherSpots: spot.kind == .weatherSpot
        case .marineStations, .airports: false
        }
    }
}

enum CuratedWeatherSpots {
    static let all: [MapSpot] = [
        MapSpot(
            id: "curated:gandy-bridge",
            name: "Gandy Bridge",
            latitude: 27.8936,
            longitude: -82.5415,
            kind: .weatherSpot,
            provider: "SeaSignal curated location",
            details: [
                "Area": "Old Tampa Bay",
                "Purpose": "Compare nearby modeled, airport, and marine observations",
                "Sensor note": "This pin marks a weather-interest location, not a dedicated weather sensor."
            ]
        )
    ]
}
