import Foundation
import MapKit

struct OpenMeteoWindLocation: Decodable {
    let latitude: Double
    let longitude: Double
    let hourly: Hourly

    struct Hourly: Decodable {
        let time: [String]
        let wind_speed_10m: [Double?]
        let wind_direction_10m: [Double?]
    }
}

struct WindGridProvider: Sendable {
    let rows: Int
    let columns: Int

    init(rows: Int = 7, columns: Int = 7) {
        self.rows = rows
        self.columns = columns
    }

    func fetch(in region: MKCoordinateRegion, offsetHours: Int) async throws -> WindField {
        if let cached = await MapDiskCache.shared.windValue(for: region, offsetHours: offsetHours) { return cached }

        do {
            let request = try makeURL(region: region)
            let (data, response) = try await URLSession.shared.data(from: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let field = try Self.decode(
                data,
                region: region,
                rows: rows,
                columns: columns,
                targetDate: Calendar.current.date(byAdding: .hour, value: offsetHours, to: Date()) ?? Date()
            )
            await MapDiskCache.shared.store(wind: field, for: region, offsetHours: offsetHours)
            return field
        } catch {
            if let stale = await MapDiskCache.shared.staleWind(for: region, offsetHours: offsetHours) {
                return stale.markedStale()
            }
            throw error
        }
    }

    static func decode(
        _ data: Data,
        region: MKCoordinateRegion,
        rows: Int,
        columns: Int,
        targetDate: Date
    ) throws -> WindField {
        let decoder = JSONDecoder()
        let locations: [OpenMeteoWindLocation]
        if let array = try? decoder.decode([OpenMeteoWindLocation].self, from: data) {
            locations = array
        } else {
            locations = [try decoder.decode(OpenMeteoWindLocation.self, from: data)]
        }
        guard locations.count == rows * columns else { throw WindGridError.incompleteGrid }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var u: [Double] = []
        var v: [Double] = []
        var speed: [Double] = []
        var validDates: [Date] = []
        for location in locations {
            let dates = location.hourly.time.compactMap(formatter.date)
            guard let index = dates.indices.min(by: {
                abs(dates[$0].timeIntervalSince(targetDate)) < abs(dates[$1].timeIntervalSince(targetDate))
            }),
            let speedValue = location.hourly.wind_speed_10m[safe: index] ?? nil,
            let direction = location.hourly.wind_direction_10m[safe: index] ?? nil else {
                throw WindGridError.missingWindValue
            }
            let sample = WindSample(speedKnots: speedValue, directionDegrees: direction)
            u.append(sample.u)
            v.append(sample.v)
            speed.append(speedValue)
            validDates.append(dates[index])
        }

        let box = GeoMath.boundingBox(region)
        return WindField(
            rows: rows,
            columns: columns,
            minLatitude: box.south,
            maxLatitude: box.north,
            minLongitude: box.west,
            maxLongitude: box.east,
            u: u,
            v: v,
            speed: speed,
            validAt: validDates.first ?? targetDate,
            fetchedAt: Date(),
            isStale: false
        )
    }

    private func makeURL(region: MKCoordinateRegion) throws -> URL {
        let box = GeoMath.boundingBox(region)
        var latitudes: [String] = []
        var longitudes: [String] = []
        for row in 0..<rows {
            let latitude = box.south + (box.north - box.south) * Double(row) / Double(max(1, rows - 1))
            for column in 0..<columns {
                let longitude = box.west + (box.east - box.west) * Double(column) / Double(max(1, columns - 1))
                latitudes.append(String(format: "%.4f", latitude))
                longitudes.append(String(format: "%.4f", longitude))
            }
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: latitudes.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: longitudes.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "past_hours", value: "6"),
            URLQueryItem(name: "forecast_hours", value: "84")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }
}

enum WindGridError: Error {
    case incompleteGrid
    case missingWindValue
}

private extension WindField {
    func markedStale() -> WindField {
        WindField(
            rows: rows, columns: columns,
            minLatitude: minLatitude, maxLatitude: maxLatitude,
            minLongitude: minLongitude, maxLongitude: maxLongitude,
            u: u, v: v, speed: speed,
            validAt: validAt, fetchedAt: fetchedAt, isStale: true
        )
    }
}
