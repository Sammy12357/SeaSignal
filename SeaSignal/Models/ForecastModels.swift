import Foundation
import CoreLocation

struct WindSample: Identifiable, Hashable {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let speedKPH: Double
    let directionFromDegrees: Double
    let gustKPH: Double?

    var id: String {
        "\(coordinate.latitude),\(coordinate.longitude),\(timestamp.timeIntervalSince1970)"
    }

    static func == (lhs: WindSample, rhs: WindSample) -> Bool {
        lhs.id == rhs.id && lhs.speedKPH == rhs.speedKPH &&
        lhs.directionFromDegrees == rhs.directionFromDegrees && lhs.gustKPH == rhs.gustKPH
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(speedKPH)
        hasher.combine(directionFromDegrees)
        hasher.combine(gustKPH)
    }

    var vector: WindVector {
        WindVector.fromMeteorological(
            speedKPH: speedKPH,
            directionFromDegrees: directionFromDegrees
        )
    }
}

struct MarineSample: Hashable {
    let timestamp: Date
    let waveHeightMeters: Double?
    let waveDirectionDegrees: Double?
    let wavePeriodSeconds: Double?
    let currentVelocityKPH: Double?
    let currentDirectionDegrees: Double?
}

struct ForecastPoint: Identifiable, Hashable {
    let launchID: String
    let wind: WindSample
    let marine: MarineSample?
    var id: String { "\(launchID)-\(wind.id)" }
}

struct WindVector: Hashable {
    let eastMetersPerSecond: Double
    let northMetersPerSecond: Double

    var speedMetersPerSecond: Double {
        hypot(eastMetersPerSecond, northMetersPerSecond)
    }

    static func fromMeteorological(speedKPH: Double, directionFromDegrees: Double) -> WindVector {
        let speed = speedKPH / 3.6
        let travelRadians = (directionFromDegrees + 180) * .pi / 180
        return WindVector(
            eastMetersPerSecond: speed * sin(travelRadians),
            northMetersPerSecond: speed * cos(travelRadians)
        )
    }
}

struct WindField: Hashable {
    let samples: [WindSample]
    let timestamp: Date

    func vector(near coordinate: CLLocationCoordinate2D) -> WindVector {
        guard !samples.isEmpty else {
            return WindVector(eastMetersPerSecond: 0, northMetersPerSecond: 0)
        }

        let nearest = samples.map { sample -> (WindSample, Double) in
            let latitudeDelta = sample.coordinate.latitude - coordinate.latitude
            let longitudeDelta = sample.coordinate.longitude - coordinate.longitude
            return (sample, latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(4)

        var totalWeight = 0.0
        var east = 0.0
        var north = 0.0
        for (sample, distanceSquared) in nearest {
            let weight = 1 / max(distanceSquared, 0.000001)
            east += sample.vector.eastMetersPerSecond * weight
            north += sample.vector.northMetersPerSecond * weight
            totalWeight += weight
        }
        return WindVector(
            eastMetersPerSecond: east / totalWeight,
            northMetersPerSecond: north / totalWeight
        )
    }
}

extension CLLocationCoordinate2D {
    func advanced(by vector: WindVector, seconds: TimeInterval, visualScale: Double = 140) -> CLLocationCoordinate2D {
        let latitudeDelta = vector.northMetersPerSecond * seconds * visualScale / 111_320
        let longitudeScale = max(cos(latitude * .pi / 180), 0.2)
        let longitudeDelta = vector.eastMetersPerSecond * seconds * visualScale / (111_320 * longitudeScale)
        return CLLocationCoordinate2D(latitude: latitude + latitudeDelta, longitude: longitude + longitudeDelta)
    }
}
