import CoreLocation
import MapKit
import XCTest
@testable import SeaSignal

@MainActor
final class MapFeatureTests: XCTestCase {
    func testWindFieldBilinearInterpolation() throws {
        let field = WindField(
            rows: 2, columns: 2,
            minLatitude: 0, maxLatitude: 2,
            minLongitude: 0, maxLongitude: 2,
            u: [0, 10, 20, 30],
            v: [0, -10, -20, -30],
            speed: [0, 10, 20, 30],
            validAt: Date(), fetchedAt: Date(), isStale: false
        )

        let sample = try XCTUnwrap(field.sample(at: CLLocationCoordinate2D(latitude: 1, longitude: 1)))
        XCTAssertEqual(sample.speed, 15, accuracy: 0.001)
        XCTAssertEqual(sample.u, 15, accuracy: 0.001)
        XCTAssertEqual(sample.v, -15, accuracy: 0.001)

        let clamped = try XCTUnwrap(field.sampleClamped(to: CLLocationCoordinate2D(latitude: 4, longitude: -2)))
        XCTAssertEqual(clamped.speed, 20, accuracy: 0.001)
    }

    func testOverpassDecodesNodeAndWayCenter() throws {
        let data = try fixture(named: "overpass_spots")
        let spots = try OverpassProvider.decode(data)

        XCTAssertEqual(spots.count, 2)
        XCTAssertTrue(spots.contains { $0.name == "Ballast Point Ramp" && $0.kind == .ramp })
        XCTAssertTrue(spots.contains { $0.name == "Fishing pier" && $0.kind == .pier })
    }

    func testWindGridDecoderUsesNearestHour() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let target = try XCTUnwrap(formatter.date(from: "2026-07-21T12:05"))
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 28, longitude: -82.5),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
        let field = try WindGridProvider.decode(
            fixture(named: "wind_grid"),
            region: region,
            rows: 2,
            columns: 2,
            targetDate: target
        )

        XCTAssertEqual(field.speed, [8, 10, 12, 14])
        XCTAssertEqual(field.rows, 2)
        XCTAssertEqual(field.columns, 2)
    }

    func testFavoriteWinsWhenMergingNearbyDiscovery() {
        let favorite = MapSpot(id: "favorite:1", name: "My Ramp", latitude: 28, longitude: -82.5, kind: .ramp)
        let duplicate = MapSpot(id: "osm:node:1", name: "Public boat ramp", latitude: 28.0001, longitude: -82.5, kind: .ramp)
        let pier = MapSpot(id: "osm:node:2", name: "Pier", latitude: 28.02, longitude: -82.5, kind: .pier)

        let merged = MapTabViewModel.merge(discovered: [duplicate, pier], favorites: [favorite])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first, favorite)
        XCTAssertTrue(merged.contains(pier))
    }

    func testOverpassDedupePrefersNamedLocation() {
        let generic = MapSpot(id: "1", name: "Public boat ramp", latitude: 28, longitude: -82.5, kind: .ramp)
        let named = MapSpot(id: "2", name: "Davis Islands Ramp", latitude: 28.0001, longitude: -82.5, kind: .ramp)

        let result = OverpassProvider.deduplicate([generic, named])

        XCTAssertEqual(result, [named])
    }

    private func fixture(named name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
