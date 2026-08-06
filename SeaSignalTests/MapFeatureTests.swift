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

        // The fixture contains a `man_made=pier` way (id 202) which must now be skipped.
        XCTAssertEqual(spots.count, 3)
        XCTAssertFalse(spots.contains { $0.kind == .pier })
        XCTAssertTrue(spots.contains { $0.name == "Ballast Point Ramp" && $0.kind == .ramp })
        XCTAssertTrue(spots.contains { $0.name == "Trailer Ramp" && $0.details?["Fee"] == "yes" })
        XCTAssertTrue(spots.contains { $0.name == "Kayak Put-in" && $0.details?["Canoe"] == "yes" })
    }

    func testFloridaInventoryDecodesOfficialBallastPointRecord() throws {
        let data = Data("""
        {
          "features": [{
            "attributes": {
              "RampID": "HL00179JY",
              "RampType": "Stand Alone Ramp",
              "RampName": "Ballast Point Park Public Boat Ramp",
              "AccessType": "Government Owned for General Public Use",
              "PrimaryAdminEntity": "City of Tampa",
              "Status": "Open for Business",
              "Street1": "5300 Interbay Blvd",
              "City": "Tampa", "StateCode": "FL", "ZipCode": "33611",
              "TotalLanes": 2, "Trailer": 20,
              "WaterBodyName": "Hillsborough Bay",
              "last_edited_date": 1751328000000
            },
            "geometry": { "x": -82.4809250001, "y": 27.8894769997 }
          }],
          "exceededTransferLimit": false
        }
        """.utf8)

        let result = try FloridaBoatRampProvider.decode(data)
        let spot = try XCTUnwrap(result.spots.first)

        XCTAssertEqual(result.spots.count, 1)
        XCTAssertEqual(spot.id, "fwc:HL00179JY")
        XCTAssertEqual(spot.name, "Ballast Point Park Public Boat Ramp")
        XCTAssertEqual(spot.latitude, 27.8894769997, accuracy: 0.0000001)
        XCTAssertEqual(spot.longitude, -82.4809250001, accuracy: 0.0000001)
        XCTAssertEqual(spot.verificationLevel, .official)
        XCTAssertEqual(spot.accessType, .publicAccess)
        XCTAssertEqual(spot.operationalStatus, .open)
        XCTAssertEqual(spot.facilityType, .motorized)
        XCTAssertEqual(spot.coordinateType, .physicalRamp)
        XCTAssertEqual(spot.details?["Operator"], "City of Tampa")
        XCTAssertEqual(spot.details?["Launch lanes"], "2")
        XCTAssertNotNil(spot.lastVerifiedAt)
    }

    func testFloridaInventoryExcludesPrivateClosedAndSeaplaneRecords() throws {
        func feature(id: String, type: String, access: String, status: String) -> String {
            """
            {"attributes":{"RampID":"\(id)","RampType":"\(type)","RampName":"Test \(id)","AccessType":"\(access)","Status":"\(status)"},"geometry":{"x":-82.5,"y":28.0}}
            """
        }
        let json = """
        {"features":[
          \(feature(id: "PRIVATE", type: "Stand Alone Ramp", access: "Private", status: "Open for Business")),
          \(feature(id: "CLOSED", type: "Stand Alone Ramp", access: "Government Owned for General Public Use", status: "Permanently Closed")),
          \(feature(id: "PLANE", type: "Seaplane Ramp", access: "Government Owned for General Public Use", status: "Open for Business"))
        ]}
        """

        XCTAssertTrue(try FloridaBoatRampProvider.decode(Data(json.utf8)).spots.isEmpty)
    }

    func testFloridaInventoryCorrectsKnownSourceTypoButRetainsAlias() throws {
        let json = """
        {"features":[{"attributes":{"RampID":"HL00002AA","RampType":"Hand Launch Only","RampName":"Cyoress Point Park Paddlecraft Launch","AccessType":"Government Owned for General Public Use","Status":"Open for Business"},"geometry":{"x":-82.55,"y":27.96}}]}
        """
        let spot = try XCTUnwrap(FloridaBoatRampProvider.decode(Data(json.utf8)).spots.first)

        XCTAssertEqual(spot.name, "Cypress Point Park Paddlecraft Launch")
        XCTAssertEqual(spot.aliases, ["Cyoress Point Park Paddlecraft Launch"])
        XCTAssertEqual(spot.facilityType, .paddle)
    }

    func testOverpassRejectsPrivateAndAmbiguousWaterAccessPoints() throws {
        let json = """
        {"elements":[
          {"type":"node","id":1,"lat":28.0,"lon":-82.5,"tags":{"leisure":"slipway","access":"private","name":"Private Ramp"}},
          {"type":"node","id":2,"lat":28.0,"lon":-82.51,"tags":{"waterway":"access_point","name":"Ambiguous Access"}},
          {"type":"node","id":3,"lat":28.0,"lon":-82.52,"tags":{"waterway":"access_point","boat":"designated","name":"Public Access"}}
        ]}
        """
        let spots = try OverpassProvider.decode(Data(json.utf8))

        XCTAssertEqual(spots.map(\.id), ["osm:node:3"])
    }

    func testRampNameClassifierRejectsRentalsAndAcceptsRealLaunches() {
        XCTAssertFalse(RampNameClassifier.isLikelyLaunch("Tampa Boat and Jet Ski Rentals"))
        XCTAssertFalse(RampNameClassifier.isLikelyLaunch("Cruisin' Tikis Tampa"))
        XCTAssertTrue(RampNameClassifier.isLikelyLaunch("Ballast Point Public Boat Ramp"))
        XCTAssertTrue(RampNameClassifier.isLikelyLaunch("Cypress Point Kayak Launch"))
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

    func testAirportMETARDecoderHandlesVariableWindAndKeepsLatestReport() throws {
        let json = """
        [
          {
            "icaoId": "KTPA", "name": "Tampa Intl", "lat": 27.9633, "lon": -82.54,
            "obsTime": 1784829180, "wdir": 220, "wspd": 6, "visib": "10+",
            "temp": 31.1, "dewp": 24.4, "altim": 1018, "rawOb": "METAR KTPA OLD"
          },
          {
            "icaoId": "KTPA", "name": "Tampa Intl", "lat": 27.9633, "lon": -82.54,
            "obsTime": 1784832780, "wdir": "VRB", "wspd": 8, "wgst": 14,
            "temp": 32.2, "dewp": 23.9, "altim": 1017.4, "rawOb": "METAR KTPA NEW"
          }
        ]
        """

        let observations = try AirportWeatherProvider.decode(Data(json.utf8))
        let airport = try XCTUnwrap(observations.first)

        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(airport.stationID, "KTPA")
        XCTAssertNil(airport.windDirectionDegrees)
        XCTAssertEqual(airport.windSpeedKnots, 8)
        XCTAssertEqual(airport.gustKnots, 14)
        XCTAssertEqual(airport.rawReport, "METAR KTPA NEW")
    }

    func testGandyBridgeCuratedWeatherSpot() throws {
        let spot = try XCTUnwrap(CuratedWeatherSpots.all.first { $0.id == "curated:gandy-bridge" })
        XCTAssertEqual(spot.kind, .weatherSpot)
        XCTAssertEqual(spot.name, "Gandy Bridge")
        XCTAssertTrue(spot.latitude > 27.8 && spot.latitude < 28.0)
        XCTAssertTrue(spot.longitude < -82.4 && spot.longitude > -82.7)
        XCTAssertNotNil(spot.details?["Sensor note"])
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

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, named.id)
        XCTAssertEqual(result.first?.aliases, [generic.name])
    }

    // MARK: - Individual pins vs. clustering

    func testSpotsRenderIndividuallyAtBoatingZoom() {
        let spots = Self.gridSpots(count: 80, baseLatitude: 27.90, baseLongitude: -82.50, spacing: 0.01)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.94, longitude: -82.46),
            span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.30)
        )

        let items = MapTabViewModel().displayItems(
            filter: .all, favoritesOnly: false, favorites: spots, region: region
        )

        // Would have clustered under the old thresholds (span > 0.18 or count > 70).
        XCTAssertEqual(items.count, spots.count)
        XCTAssertEqual(Self.clusterCount(in: items), 0)
    }

    func testClusteringStillEngagesAtContinentalZoom() {
        let spots = Self.gridSpots(count: 500, baseLatitude: 27.0, baseLongitude: -83.0, spacing: 0.05)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.55, longitude: -82.45),
            span: MKCoordinateSpan(latitudeDelta: 3.0, longitudeDelta: 3.0)
        )

        let items = MapTabViewModel().displayItems(
            filter: .all, favoritesOnly: false, favorites: spots, region: region
        )

        XCTAssertGreaterThan(Self.clusterCount(in: items), 0)
    }

    // MARK: - Piers

    func testLegacyPierStillDecodesButIsNotDisplayed() throws {
        let pier = MapSpot(id: "legacy:pier", name: "Old Pier", latitude: 27.95, longitude: -82.46, kind: .pier)
        let ramp = MapSpot(id: "legacy:ramp", name: "Ballast Point", latitude: 27.90, longitude: -82.51, kind: .ramp)

        // Data written by earlier builds must still decode; removing the enum case would
        // break MapDiskCache and persisted favourites on upgrade.
        let decoded = try JSONDecoder().decode(MapSpot.self, from: try JSONEncoder().encode(pier))
        XCTAssertEqual(decoded.kind, .pier)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.93, longitude: -82.49),
            span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.30)
        )
        let items = MapTabViewModel().displayItems(
            filter: .all, favoritesOnly: false, favorites: [pier, ramp], region: region
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items.contains { item in
            if case .spot(let spot) = item { return spot.kind == .pier }
            return false
        })
    }

    // MARK: - Dedupe precedence

    func testDedupePrefersRampOverPier() {
        let pier = MapSpot(id: "a", name: "Pier", latitude: 28, longitude: -82.5, kind: .pier)
        let ramp = MapSpot(id: "b", name: "Ramp", latitude: 28.0003, longitude: -82.5, kind: .ramp)

        let result = SpotDeduplicator.deduplicate([pier, ramp])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, ramp.id)
    }

    func testDedupeKeepsFavoriteOverDiscovery() {
        // IDs chosen so the discovered spot would win the lexicographic tiebreak;
        // only the favourite rule should save the favourite.
        let favorite = MapSpot(id: "z:favorite", name: "My Ramp", latitude: 28, longitude: -82.5, kind: .ramp)
        let discovered = MapSpot(id: "a:osm", name: "Riverside Ramp", latitude: 28.0002, longitude: -82.5, kind: .ramp)

        let result = SpotDeduplicator.deduplicate([favorite, discovered]) { $0.id == favorite.id }

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, favorite.id)
    }

    func testDedupeKeepsDistinctNearbyRamps() {
        let north = MapSpot(id: "1", name: "North Ramp", latitude: 28, longitude: -82.5, kind: .ramp)
        let south = MapSpot(id: "2", name: "South Ramp", latitude: 28.0018, longitude: -82.5, kind: .ramp)

        XCTAssertEqual(SpotDeduplicator.deduplicate([north, south]).count, 2)
    }

    func testDedupePrefersOfficialRecordForSameNearbyFacility() {
        let official = MapSpot(
            id: "fwc:HL00179JY", name: "Ballast Point Park Public Boat Ramp",
            latitude: 27.88947, longitude: -82.48092, kind: .ramp, provider: "Florida FWC",
            canonicalID: "fwc:HL00179JY", sourceID: "HL00179JY", verificationLevel: .official
        )
        let osm = MapSpot(
            id: "osm:node:42", name: "Ballast Point Boat Ramp",
            latitude: 27.88960, longitude: -82.48080, kind: .ramp, provider: "OpenStreetMap",
            sourceID: "node:42", verificationLevel: .communityConfirmed
        )

        let result = SpotDeduplicator.deduplicate([osm, official])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, official.id)
        XCTAssertEqual(result.first?.aliases, [osm.name])
    }

    func testDedupeNeverCollapsesDistinctOfficialIDsWithinOneThousandFeet() {
        let north = MapSpot(
            id: "fwc:A", name: "North Basin Ramp", latitude: 28, longitude: -82.5,
            kind: .ramp, provider: "Florida FWC", canonicalID: "fwc:A", verificationLevel: .official
        )
        let south = MapSpot(
            id: "fwc:B", name: "South Basin Ramp", latitude: 28.0001, longitude: -82.5,
            kind: .ramp, provider: "Florida FWC", canonicalID: "fwc:B", verificationLevel: .official
        )

        XCTAssertEqual(SpotDeduplicator.deduplicate([north, south]).count, 2)
    }

    func testLegacyMapSpotDecodesWithoutCatalogMetadata() throws {
        let json = """
        {"id":"legacy","name":"Legacy Ramp","latitude":28,"longitude":-82.5,"kind":"ramp"}
        """
        let spot = try JSONDecoder().decode(MapSpot.self, from: Data(json.utf8))

        XCTAssertNil(spot.canonicalID)
        XCTAssertNil(spot.verificationLevel)
        XCTAssertEqual(spot.name, "Legacy Ramp")
    }

    func testDedupeIsStableRegardlessOfInputOrder() {
        let spots = [
            MapSpot(id: "1", name: "Public boat ramp", latitude: 28, longitude: -82.5, kind: .ramp),
            MapSpot(id: "2", name: "Davis Islands Ramp", latitude: 28.0001, longitude: -82.5, kind: .ramp),
            MapSpot(id: "3", name: "Far Ramp", latitude: 28.05, longitude: -82.5, kind: .ramp)
        ]

        XCTAssertEqual(
            SpotDeduplicator.deduplicate(spots).map(\.id),
            SpotDeduplicator.deduplicate(spots.reversed()).map(\.id)
        )
    }

    // MARK: - Zoom

    func testZoomRoundTripReturnsToOriginalSpan() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46),
            span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.25)
        )

        let zoomedIn = GeoMath.zoomedRegion(region, scale: 0.5)
        let restored = GeoMath.zoomedRegion(zoomedIn, scale: 2.0)

        XCTAssertEqual(zoomedIn.span.latitudeDelta, 0.15, accuracy: 0.0001)
        XCTAssertEqual(restored.span.latitudeDelta, region.span.latitudeDelta, accuracy: 0.0001)
        XCTAssertEqual(restored.span.longitudeDelta, region.span.longitudeDelta, accuracy: 0.0001)
    }

    func testZoomClampsAtBounds() {
        var region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46),
            span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.25)
        )

        for _ in 0..<40 { region = GeoMath.zoomedRegion(region, scale: 0.5) }
        XCTAssertGreaterThanOrEqual(region.span.latitudeDelta, 0.002)

        for _ in 0..<40 { region = GeoMath.zoomedRegion(region, scale: 2.0) }
        XCTAssertLessThanOrEqual(region.span.latitudeDelta, 120)
        XCTAssertLessThanOrEqual(region.span.longitudeDelta, 180)
    }

    // MARK: - Fetch tile quantisation

    func testFetchTileIsStableAcrossSmallPans() {
        let base = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46),
            span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.30)
        )
        let panned = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.96, longitude: -82.45),
            span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.30)
        )

        let first = GeoMath.fetchTile(for: base)
        let second = GeoMath.fetchTile(for: panned)

        // Identical tiles mean one Overpass query and one cache entry serve both views,
        // which is what stops pins reshuffling and stops every zoom hitting the network.
        XCTAssertEqual(first.center.latitude, second.center.latitude, accuracy: 0.000001)
        XCTAssertEqual(first.center.longitude, second.center.longitude, accuracy: 0.000001)
        XCTAssertEqual(first.span.latitudeDelta, second.span.latitudeDelta, accuracy: 0.000001)
    }

    func testFetchTileDiffersAcrossZoomBuckets() {
        let center = CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46)
        let close = GeoMath.fetchTile(for: MKCoordinateRegion(
            center: center, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))
        let wide = GeoMath.fetchTile(for: MKCoordinateRegion(
            center: center, span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0)
        ))

        XCTAssertNotEqual(close.span.latitudeDelta, wide.span.latitudeDelta, accuracy: 0.000001)
    }

    func testFetchTileCoversItsSourceRegion() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46),
            span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.30)
        )
        let tile = GeoMath.fetchTile(for: region)
        let box = GeoMath.boundingBox(region)

        for latitude in [box.south, box.north] {
            for longitude in [box.west, box.east] {
                XCTAssertTrue(
                    GeoMath.contains(tile, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)),
                    "tile must cover the visible corner \(latitude), \(longitude)"
                )
            }
        }
    }

    func testFetchTileIsClampedForExtremeSpans() {
        let center = CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46)
        let tiny = GeoMath.fetchTile(for: MKCoordinateRegion(
            center: center, span: MKCoordinateSpan(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
        ))
        let huge = GeoMath.fetchTile(for: MKCoordinateRegion(
            center: center, span: MKCoordinateSpan(latitudeDelta: 90, longitudeDelta: 90)
        ))

        XCTAssertEqual(tiny.span.latitudeDelta, 0.06, accuracy: 0.000001)   // 0.03 floor, doubled
        XCTAssertEqual(huge.span.latitudeDelta, 8.0, accuracy: 0.000001)    // 4.0 ceiling, doubled
    }

    // MARK: - Spots are never discarded

    func testAccumulateKeepsExistingSpots() {
        let existing = [
            MapSpot(id: "osm:node:1", name: "Ballast Point", latitude: 27.90, longitude: -82.51, kind: .ramp),
            MapSpot(id: "osm:node:2", name: "Davis Islands", latitude: 27.88, longitude: -82.45, kind: .ramp)
        ]
        let found = [
            MapSpot(id: "osm:node:3", name: "Picnic Island", latitude: 27.86, longitude: -82.55, kind: .ramp)
        ]

        let result = MapTabViewModel.accumulate(
            existing: existing,
            found: found,
            favorites: [],
            around: CLLocationCoordinate2D(latitude: 27.89, longitude: -82.50)
        )

        let ids = Set(result.map(\.id))
        XCTAssertTrue(ids.contains("osm:node:1"))
        XCTAssertTrue(ids.contains("osm:node:2"))
        XCTAssertTrue(ids.contains("osm:node:3"))
    }

    func testAccumulateBoundsGrowthToNearestSpots() {
        let center = CLLocationCoordinate2D(latitude: 28.0, longitude: -82.5)
        let existing = Self.gridSpots(count: 60, baseLatitude: 28.0, baseLongitude: -82.5, spacing: 0.02)

        let result = MapTabViewModel.accumulate(
            existing: existing, found: [], favorites: [], around: center, limit: 20
        )

        XCTAssertLessThanOrEqual(result.count, 20 + CuratedWeatherSpots.all.count)
    }

    func testClusteringEngagesAboveCountThreshold() {
        let spots = Self.gridSpots(count: 200, baseLatitude: 27.85, baseLongitude: -82.60, spacing: 0.005)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.885, longitude: -82.565),
            span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.30)
        )

        let items = MapTabViewModel().displayItems(
            filter: .all, favoritesOnly: false, favorites: spots, region: region
        )

        // 200 > clusterCountThreshold (150), so the performance guard should engage.
        XCTAssertGreaterThan(Self.clusterCount(in: items), 0)
    }

    // MARK: - Helpers

    /// Grid of ramps spaced well beyond the dedupe radius so none are collapsed.
    private static func gridSpots(
        count: Int,
        baseLatitude: Double,
        baseLongitude: Double,
        spacing: Double
    ) -> [MapSpot] {
        let side = Int(Double(count).squareRoot().rounded(.up))
        return (0..<count).map { index in
            MapSpot(
                id: String(format: "test:%04d", index),
                name: "Ramp \(index)",
                latitude: baseLatitude + Double(index / side) * spacing,
                longitude: baseLongitude + Double(index % side) * spacing,
                kind: .ramp
            )
        }
    }

    private static func clusterCount(in items: [MapDisplayItem]) -> Int {
        items.filter { if case .cluster = $0 { return true } else { return false } }.count
    }

    private func fixture(named name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
