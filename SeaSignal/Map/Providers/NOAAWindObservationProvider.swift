import Foundation
import MapKit

actor NOAAWindObservationProvider {
    private static let observationsURL = URL(string: "https://www.ndbc.noaa.gov/data/latest_obs/latest_obs.txt")!
    private static let stationsURL = URL(string: "https://www.ndbc.noaa.gov/activestations.xml")!
    private static let cacheLifetime: TimeInterval = 15 * 60
    private static let maximumObservationAge: TimeInterval = 6 * 60 * 60
    private static let maximumVisibleStations = 36

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(in region: MKCoordinateRegion) async throws -> WindObservationSnapshot {
        if let cached = await MapDiskCache.shared.windObservations(maximumAge: Self.cacheLifetime) {
            return snapshot(from: cached, in: region, isStale: false)
        }

        do {
            async let stationResponse = try? session.data(from: Self.stationsURL)
            let (observationData, response) = try await session.data(from: Self.observationsURL)
            try Self.validate(response)

            let metadataResult = await stationResponse
            let stationNames: [String: String]
            if let (metadataData, metadataResponse) = metadataResult,
               (metadataResponse as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true {
                stationNames = Self.decodeStationNames(metadataData)
            } else {
                stationNames = [:]
            }

            let now = Date()
            let decoded = try Self.decodeObservations(observationData, stationNames: stationNames)
            let recent = decoded.filter {
                let age = now.timeIntervalSince($0.observedAt)
                return age >= -60 * 60 && age <= Self.maximumObservationAge
            }
            await MapDiskCache.shared.store(windObservations: recent)
            return snapshot(from: recent, in: region, isStale: false)
        } catch {
            if let cached = await MapDiskCache.shared.staleWindObservations() {
                return snapshot(from: cached, in: region, isStale: true)
            }
            throw error
        }
    }

    static func decodeObservations(
        _ data: Data,
        stationNames: [String: String] = [:]
    ) throws -> [WindObservation] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NOAAWindObservationError.invalidEncoding
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let values = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard values.count >= 11,
                  let latitude = Double(values[1]),
                  let longitude = Double(values[2]),
                  let year = Int(values[3]),
                  let month = Int(values[4]),
                  let day = Int(values[5]),
                  let hour = Int(values[6]),
                  let minute = Int(values[7]),
                  let direction = measurement(values[8]),
                  let speedMetresPerSecond = measurement(values[9]),
                  let observedAt = calendar.date(from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                  )) else {
                return nil
            }

            let stationID = values[0].uppercased()
            let gust = measurement(values[10]).map(Self.metresPerSecondToKnots)
            return WindObservation(
                stationID: stationID,
                stationName: stationNames[stationID] ?? "NOAA Station \(stationID)",
                latitude: latitude,
                longitude: longitude,
                speedKnots: Self.metresPerSecondToKnots(speedMetresPerSecond),
                directionDegrees: direction,
                gustKnots: gust,
                observedAt: observedAt
            )
        }
    }

    static func decodeStationNames(_ data: Data) -> [String: String] {
        let delegate = NOAAStationXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [:] }
        return delegate.names
    }

    private func snapshot(
        from observations: [WindObservation],
        in region: MKCoordinateRegion,
        isStale: Bool
    ) -> WindObservationSnapshot {
        let visible = observations
            .filter { GeoMath.contains(region, coordinate: $0.coordinate) }
            .sorted {
                GeoMath.distance($0.coordinate, region.center) < GeoMath.distance($1.coordinate, region.center)
            }
            .prefix(Self.maximumVisibleStations)
        return WindObservationSnapshot(
            observations: Array(visible),
            fetchedAt: Date(),
            isStale: isStale
        )
    }

    private static func measurement(_ value: String) -> Double? {
        guard value != "MM" else { return nil }
        return Double(value)
    }

    private static func metresPerSecondToKnots(_ value: Double) -> Double {
        value * 1.943_844_492_440_6
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

enum NOAAWindObservationError: Error {
    case invalidEncoding
}

private final class NOAAStationXMLDelegate: NSObject, XMLParserDelegate {
    var names: [String: String] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "station",
              let id = attributeDict["id"]?.uppercased(),
              let name = attributeDict["name"],
              !name.isEmpty else { return }
        names[id] = name
    }
}
