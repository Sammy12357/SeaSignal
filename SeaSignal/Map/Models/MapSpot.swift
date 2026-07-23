import CoreLocation
import Foundation

enum SpotKind: String, Codable, Hashable, Sendable, CaseIterable {
    case ramp
    case pier

    var glyph: String { self == .ramp ? "ferry.fill" : "figure.fishing" }
    var label: String { self == .ramp ? "Boat ramp" : "Fishing pier" }
}

struct MapSpot: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let kind: SpotKind

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

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func matches(_ spot: MapSpot) -> Bool {
        switch self {
        case .all: true
        case .ramps: spot.kind == .ramp
        case .piers: spot.kind == .pier
        }
    }
}
