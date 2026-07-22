import CoreLocation
import Foundation

enum WindLayerMode: String, CaseIterable, Identifiable {
    case hybrid
    case modeled
    case observations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hybrid: "Hybrid"
        case .modeled: "Modeled"
        case .observations: "Stations"
        }
    }

    var systemImage: String {
        switch self {
        case .hybrid: "point.3.connected.trianglepath.dotted"
        case .modeled: "wind"
        case .observations: "dot.radiowaves.left.and.right"
        }
    }

    var detail: String {
        switch self {
        case .hybrid:
            "Combines the continuous Open-Meteo wind field with current NOAA station measurements. Station markers appear at Now."
        case .modeled:
            "Shows the continuous modeled wind field and forecast timeline without station markers."
        case .observations:
            "Shows recent measured wind from NOAA buoys and coastal stations without a modeled overlay."
        }
    }

    var showsModeledWind: Bool { self != .observations }
    var showsObservations: Bool { self != .modeled }
}

struct WindSample: Codable, Hashable, Sendable {
    let speedKnots: Double
    let directionDegrees: Double

    var u: Double { -speedKnots * sin(directionDegrees * .pi / 180) }
    var v: Double { -speedKnots * cos(directionDegrees * .pi / 180) }
}

struct WindObservation: Identifiable, Codable, Hashable, Sendable {
    let stationID: String
    let stationName: String
    let latitude: Double
    let longitude: Double
    let speedKnots: Double
    let directionDegrees: Double
    let gustKnots: Double?
    let observedAt: Date

    var id: String { stationID }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var compassDirection: String {
        let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = directionDegrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        return labels[Int((positive / 45).rounded()) % labels.count]
    }
}

struct WindObservationSnapshot: Sendable {
    let observations: [WindObservation]
    let fetchedAt: Date
    let isStale: Bool
}

struct WindField: Codable, Hashable, Sendable {
    let rows: Int
    let columns: Int
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double
    let u: [Double]
    let v: [Double]
    let speed: [Double]
    let validAt: Date
    let fetchedAt: Date
    let isStale: Bool

    func sample(at coordinate: CLLocationCoordinate2D) -> (u: Double, v: Double, speed: Double)? {
        guard columns > 1, rows > 1, maxLongitude > minLongitude, maxLatitude > minLatitude else { return nil }
        let x = (coordinate.longitude - minLongitude) / (maxLongitude - minLongitude) * Double(columns - 1)
        let y = (coordinate.latitude - minLatitude) / (maxLatitude - minLatitude) * Double(rows - 1)
        guard x >= 0, x <= Double(columns - 1), y >= 0, y <= Double(rows - 1) else { return nil }
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let x1 = min(x0 + 1, columns - 1), y1 = min(y0 + 1, rows - 1)
        let tx = x - Double(x0), ty = y - Double(y0)

        func bilinear(_ values: [Double]) -> Double {
            func value(_ row: Int, _ column: Int) -> Double { values[row * columns + column] }
            let south = value(y0, x0) * (1 - tx) + value(y0, x1) * tx
            let north = value(y1, x0) * (1 - tx) + value(y1, x1) * tx
            return south * (1 - ty) + north * ty
        }
        return (bilinear(u), bilinear(v), bilinear(speed))
    }

    func sampleClamped(to coordinate: CLLocationCoordinate2D) -> (u: Double, v: Double, speed: Double)? {
        sample(at: CLLocationCoordinate2D(
            latitude: min(max(coordinate.latitude, minLatitude), maxLatitude),
            longitude: min(max(coordinate.longitude, minLongitude), maxLongitude)
        ))
    }

    func coordinate(row: Int, column: Int) -> CLLocationCoordinate2D {
        let latitude = minLatitude + (maxLatitude - minLatitude) * Double(row) / Double(max(1, rows - 1))
        let longitude = minLongitude + (maxLongitude - minLongitude) * Double(column) / Double(max(1, columns - 1))
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
