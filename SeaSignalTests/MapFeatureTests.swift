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

    func testWindFieldWaterMaskSeparatesLandAndWater() {
        let field = WindField(
            rows: 2, columns: 2,
            minLatitude: 0, maxLatitude: 2,
            minLongitude: 0, maxLongitude: 2,
            u: [0, 0, 0, 0],
            v: [0, 0, 0, 0],
            speed: [5, 5, 5, 5],
            validAt: Date(), fetchedAt: Date(), isStale: false,
            landMask: [1, 1, 0, 0]
        )

        XCTAssertFalse(field.isWater(at: CLLocationCoordinate2D(latitude: 0, longitude: 1)))
        XCTAssertTrue(field.isWater(at: CLLocationCoordinate2D(latitude: 2, longitude: 1)))
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

    func testNOAAObservationDecoderConvertsUnitsAndSkipsMissingWind() throws {
        let text = """
        #STN LAT LON YYYY MM DD hh mm WDIR WSPD GST
        SAPF1 27.761 -82.627 2026 07 21 23 18 200 9.3 10.8
        BAD01 27.800 -82.700 2026 07 21 23 00 MM MM MM
        """

        let observations = try NOAAWindObservationProvider.decodeObservations(
            Data(text.utf8),
            stationNames: ["SAPF1": "St. Petersburg, FL"]
        )

        let observation = try XCTUnwrap(observations.first)
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observation.stationName, "St. Petersburg, FL")
        XCTAssertEqual(observation.speedKnots, 18.08, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(observation.gustKnots), 20.99, accuracy: 0.01)
        XCTAssertEqual(observation.directionDegrees, 200)
        XCTAssertEqual(observation.compassDirection, "S")
    }

    func testNOAAStationMetadataDecoder() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <stations><station id="sapf1" lat="27.761" lon="-82.627" name="St. Petersburg, FL" met="y"/></stations>
        """

        let names = NOAAWindObservationProvider.decodeStationNames(Data(xml.utf8))

        XCTAssertEqual(names["SAPF1"], "St. Petersburg, FL")
    }

    func testHybridWindModeCombinesModeledAndObservedData() {
        XCTAssertTrue(WindLayerMode.hybrid.showsModeledWind)
        XCTAssertTrue(WindLayerMode.hybrid.showsObservations)
        XCTAssertFalse(WindLayerMode.modeled.showsObservations)
        XCTAssertFalse(WindLayerMode.observations.showsModeledWind)
    }

    func testMapZoomPreservesCenterAndScalesSpan() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 0.8)
        )

        let zoomedIn = GeoMath.zoomedRegion(region, scale: 0.5)
        let zoomedOut = GeoMath.zoomedRegion(region, scale: 2)

        XCTAssertEqual(zoomedIn.center.latitude, region.center.latitude)
        XCTAssertEqual(zoomedIn.center.longitude, region.center.longitude)
        XCTAssertEqual(zoomedIn.span.latitudeDelta, 0.5)
        XCTAssertEqual(zoomedIn.span.longitudeDelta, 0.4)
        XCTAssertEqual(zoomedOut.span.latitudeDelta, 2)
        XCTAssertEqual(zoomedOut.span.longitudeDelta, 1.6)
    }

    func testForecastTimelineClampsAndStopsAtBounds() {
        XCTAssertEqual(ForecastPlaybackRange.clamped(-9), -6)
        XCTAssertEqual(ForecastPlaybackRange.clamped(75), 72)
        XCTAssertEqual(ForecastPlaybackRange.nextOffset(after: -6), -3)
        XCTAssertEqual(ForecastPlaybackRange.nextOffset(after: 69), 72)
        XCTAssertNil(ForecastPlaybackRange.nextOffset(after: 72))
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
