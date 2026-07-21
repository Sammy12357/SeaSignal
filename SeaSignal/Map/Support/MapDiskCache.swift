import Foundation
import MapKit

actor MapDiskCache {
    static let shared = MapDiskCache()

    private struct SpotEntry: Codable {
        let key: String
        let spots: [MapSpot]
        let date: Date
    }
    private struct WindEntry: Codable {
        let key: String
        let field: WindField
        let date: Date
    }

    private var spots: [String: SpotEntry] = [:]
    private var wind: [String: WindEntry] = [:]
    private let spotFile: URL
    private let windFile: URL

    init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SeaSignalMap", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        spotFile = directory.appendingPathComponent("spots.json")
        windFile = directory.appendingPathComponent("wind.json")
        if let data = try? Data(contentsOf: spotFile), let values = try? JSONDecoder().decode([SpotEntry].self, from: data) {
            spots = Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0) })
        }
        if let data = try? Data(contentsOf: windFile), let values = try? JSONDecoder().decode([WindEntry].self, from: data) {
            wind = Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0) })
        }
    }

    func spotValue(for region: MKCoordinateRegion, maximumAge: TimeInterval = 20 * 60) -> [MapSpot]? {
        guard let entry = spots[key(region)], Date().timeIntervalSince(entry.date) <= maximumAge else { return nil }
        return entry.spots
    }

    func staleSpots(for region: MKCoordinateRegion) -> [MapSpot]? { spots[key(region)]?.spots }

    func store(spots value: [MapSpot], for region: MKCoordinateRegion) {
        let cacheKey = key(region)
        spots[cacheKey] = SpotEntry(key: cacheKey, spots: value, date: Date())
        if spots.count > 32 {
            spots = Dictionary(uniqueKeysWithValues: spots.values.sorted { $0.date > $1.date }.prefix(32).map { ($0.key, $0) })
        }
        persist(Array(spots.values), to: spotFile)
    }

    func windValue(for region: MKCoordinateRegion, offsetHours: Int, maximumAge: TimeInterval = 20 * 60) -> WindField? {
        guard let entry = wind[windKey(region, offsetHours: offsetHours)], Date().timeIntervalSince(entry.date) <= maximumAge else { return nil }
        return entry.field
    }

    func staleWind(for region: MKCoordinateRegion, offsetHours: Int) -> WindField? {
        wind[windKey(region, offsetHours: offsetHours)]?.field
    }

    func store(wind field: WindField, for region: MKCoordinateRegion, offsetHours: Int) {
        let cacheKey = windKey(region, offsetHours: offsetHours)
        wind[cacheKey] = WindEntry(key: cacheKey, field: field, date: Date())
        if wind.count > 56 {
            wind = Dictionary(uniqueKeysWithValues: wind.values.sorted { $0.date > $1.date }.prefix(56).map { ($0.key, $0) })
        }
        persist(Array(wind.values), to: windFile)
    }

    private func key(_ region: MKCoordinateRegion) -> String {
        let box = GeoMath.boundingBox(region)
        func rounded(_ value: Double) -> String { String(format: "%.2f", value) }
        return "\(rounded(box.south)),\(rounded(box.west)),\(rounded(box.north)),\(rounded(box.east))"
    }

    private func windKey(_ region: MKCoordinateRegion, offsetHours: Int) -> String {
        "\(key(region))|\(offsetHours)"
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
