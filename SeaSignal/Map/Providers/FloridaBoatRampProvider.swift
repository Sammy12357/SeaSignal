import Foundation
import MapKit

struct FloridaRampFetchResult: Sendable {
    let spots: [MapSpot]
    let wasTruncated: Bool
}

/// Official statewide public boat-ramp inventory maintained by the Florida Fish and
/// Wildlife Conservation Commission. Unlike a generic POI search, every returned record
/// carries a stable government ramp ID, access classification and operating status.
struct FloridaBoatRampProvider: Sendable {
    static let sourcePage = "https://myfwc.com/boating/boat-ramps-access/"
    private let endpoint = URL(string: "https://gis.myfwc.com/mapping/rest/services/Open_Data/FWC_Florida_Boat_Ramp_Inventory/MapServer/4/query")!

    static func covers(_ region: MKCoordinateRegion) -> Bool {
        let box = GeoMath.boundingBox(region)
        return box.north >= 24.3 && box.south <= 31.1 && box.east >= -87.8 && box.west <= -79.8
    }

    func fetch(in region: MKCoordinateRegion) async throws -> FloridaRampFetchResult {
        let box = GeoMath.boundingBox(region)
        guard Self.covers(region) else {
            return FloridaRampFetchResult(spots: [], wasTruncated: false)
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "where", value: "1=1"),
            URLQueryItem(name: "geometry", value: "\(box.west),\(box.south),\(box.east),\(box.north)"),
            URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "outSR", value: "4326"),
            URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
            URLQueryItem(name: "outFields", value: Self.outFields.joined(separator: ",")),
            URLQueryItem(name: "returnGeometry", value: "true"),
            URLQueryItem(name: "resultRecordCount", value: "1000"),
            URLQueryItem(name: "orderByFields", value: "RampID"),
            URLQueryItem(name: "f", value: "json")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue("SeaSignal/1.0 (iOS boating conditions app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> FloridaRampFetchResult {
        let response = try JSONDecoder().decode(ArcGISResponse.self, from: data)
        if let error = response.error {
            throw ProviderError.arcGIS(code: error.code, message: error.message)
        }
        let spots = response.features?.compactMap(makeSpot) ?? []
        return FloridaRampFetchResult(
            spots: SpotDeduplicator.deduplicate(spots),
            wasTruncated: response.exceededTransferLimit == true
        )
    }

    private static func makeSpot(_ feature: ArcGISFeature) -> MapSpot? {
        let attributes = feature.attributes
        guard let rampID = clean(attributes.RampID),
              let rawName = clean(attributes.RampName),
              let latitude = feature.geometry?.y ?? attributes.Latitude,
              let longitude = feature.geometry?.x ?? attributes.Longitude,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              let accessType = accessType(attributes.AccessType),
              let status = operationalStatus(attributes.Status),
              let facilityType = facilityType(attributes.RampType)
        else { return nil }

        // Permanently closed and destroyed facilities remain in the government archive but
        // should not be offered as places where a user can launch a boat.
        guard status != .closed else { return nil }

        let correctedName = officialNameCorrections[rampID] ?? rawName
        return MapSpot(
            id: "fwc:\(rampID)",
            name: correctedName,
            latitude: latitude,
            longitude: longitude,
            kind: .ramp,
            provider: "Florida FWC",
            details: details(attributes),
            canonicalID: "fwc:\(rampID)",
            sourceID: rampID,
            sourceURL: sourcePage,
            verificationLevel: .official,
            accessType: accessType,
            operationalStatus: status,
            facilityType: facilityType,
            coordinateType: .physicalRamp,
            lastVerifiedAt: attributes.last_edited_date.map { Date(timeIntervalSince1970: $0 / 1000) },
            aliases: correctedName == rawName ? nil : [rawName]
        )
    }

    private static func accessType(_ value: String?) -> RampAccessType? {
        switch clean(value)?.lowercased() {
        case "government owned for general public use": .publicAccess
        case "government owned for restricted public use": .restrictedPublic
        case "commercially owned for general public use": .commercialPublic
        default: nil
        }
    }

    private static func operationalStatus(_ value: String?) -> RampOperationalStatus? {
        switch clean(value)?.lowercased() {
        case "open for business": .open
        case "temporarily closed", "closed - under transition": .temporarilyClosed
        case "permanently closed", "destroyed", "closed with no further information": .closed
        case "undetermined": .undetermined
        default: nil
        }
    }

    private static func facilityType(_ value: String?) -> RampFacilityType? {
        switch clean(value)?.lowercased() {
        case "stand alone ramp": .motorized
        case "boat ramp within marina": .marina
        case "hand launch only", "hand launch for hunting": .paddle
        case "airboat ramp", "airboat/swamp buggy access": .airboat
        case "unknown": .unknown
        // A seaplane slip is not evidence of public trailer-boat access.
        case "seaplane ramp": nil
        default: nil
        }
    }

    private static func details(_ value: Attributes) -> [String: String]? {
        var result: [String: String] = [:]
        let address = [clean(value.Street1), clean(value.City), clean(value.StateCode), clean(value.ZipCode)]
            .compactMap { $0 }.joined(separator: ", ")
        if !address.isEmpty { result["Address"] = address }
        if let operatorName = clean(value.PrimaryAdminEntity) { result["Operator"] = operatorName }
        if let hours = clean(value.Hours), hours.lowercased() != "unknown" { result["Hours"] = hours }
        if let fee = feeDescription(value) { result["Fee"] = fee }
        if let surface = known(value.RampSurface) { result["Ramp surface"] = surface }
        if let condition = known(value.RampCondition) { result["Ramp condition"] = condition }
        if let lanes = value.TotalLanes { result["Launch lanes"] = String(lanes) }
        if let trailers = value.Trailer { result["Trailer parking spaces"] = String(trailers) }
        if let dock = known(value.DockType), dock.lowercased() != "none" { result["Dock"] = dock }
        if let restroom = known(value.RestroomType), restroom.lowercased() != "none" { result["Restrooms"] = restroom }
        if let accessible = known(value.AccessibilityLevel) { result["Accessibility"] = accessible }
        if let waterBody = clean(value.WaterBodyName) { result["Water body"] = waterBody }
        if let amenities = clean(value.Amenities) { result["Amenities"] = amenities }
        if let comments = clean(value.RampStatusComments) { result["Status note"] = comments }
        if let comments = clean(value.OperationalComments) { result["Operating note"] = comments }
        if let phone = clean(value.ContactPhone), phone.lowercased() != "na" { result["Contact"] = phone }
        return result.isEmpty ? nil : result
    }

    private static func feeDescription(_ value: Attributes) -> String? {
        guard let required = clean(value.isFeeRequired) else { return nil }
        if required.caseInsensitiveCompare("No") == .orderedSame { return "No" }
        if required.caseInsensitiveCompare("Yes") == .orderedSame, let amount = value.FeeAmount {
            return String(format: "Required · $%.2f", amount)
        }
        return required
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func known(_ value: String?) -> String? {
        guard let value = clean(value), value.caseInsensitiveCompare("Unknown") != .orderedSame else { return nil }
        return value
    }

    private static let officialNameCorrections: [String: String] = [
        // FWC record HL00002AA contains a one-letter typo; City of Tampa's official park
        // name is Cypress Point Park. Retain the source spelling in `aliases` for provenance.
        "HL00002AA": "Cypress Point Park Paddlecraft Launch"
    ]

    private static let outFields = [
        "RampID", "RampType", "RampName", "AccessType", "PrimaryAdminEntity", "Status",
        "Hours", "isFeeRequired", "FeeAmount", "RampSurface", "RampCondition", "TotalLanes",
        "DockType", "Trailer", "RestroomType", "AccessibilityLevel", "Street1", "City", "County",
        "StateCode", "ZipCode", "Latitude", "Longitude", "WaterBodyName", "RampStatusComments",
        "ContactPhone", "OperationalComments", "Amenities", "last_edited_date"
    ]
}

private extension FloridaBoatRampProvider {
    enum ProviderError: Error {
        case arcGIS(code: Int, message: String)
    }

    struct ArcGISResponse: Decodable {
        let features: [ArcGISFeature]?
        let exceededTransferLimit: Bool?
        let error: ArcGISError?
    }

    struct ArcGISError: Decodable {
        let code: Int
        let message: String
    }

    struct ArcGISFeature: Decodable {
        let attributes: Attributes
        let geometry: Geometry?
    }

    struct Geometry: Decodable {
        let x: Double
        let y: Double
    }

    // ArcGIS field names intentionally retain their source casing.
    struct Attributes: Decodable {
        let RampID: String?
        let RampType: String?
        let RampName: String?
        let AccessType: String?
        let PrimaryAdminEntity: String?
        let Status: String?
        let Hours: String?
        let isFeeRequired: String?
        let FeeAmount: Double?
        let RampSurface: String?
        let RampCondition: String?
        let TotalLanes: Int?
        let DockType: String?
        let Trailer: Int?
        let RestroomType: String?
        let AccessibilityLevel: String?
        let Street1: String?
        let City: String?
        let County: String?
        let StateCode: String?
        let ZipCode: String?
        let Latitude: Double?
        let Longitude: Double?
        let WaterBodyName: String?
        let RampStatusComments: String?
        let ContactPhone: String?
        let OperationalComments: String?
        let Amenities: String?
        let last_edited_date: Double?
    }
}
