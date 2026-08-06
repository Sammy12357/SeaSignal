import CoreLocation
import Foundation

enum RampVerificationLevel: String, Codable, Hashable, Sendable {
    case official
    case verified
    case communityConfirmed
    case unverified

    var label: String {
        switch self {
        case .official: "Official government record"
        case .verified: "Verified from multiple sources"
        case .communityConfirmed: "Community confirmed"
        case .unverified: "Unverified map result"
        }
    }
}

enum RampAccessType: String, Codable, Hashable, Sendable {
    case publicAccess
    case restrictedPublic
    case commercialPublic
    case privateAccess
    case unknown

    var label: String {
        switch self {
        case .publicAccess: "Public access"
        case .restrictedPublic: "Restricted public access"
        case .commercialPublic: "Public access · commercially operated"
        case .privateAccess: "Private access"
        case .unknown: "Access not verified"
        }
    }
}

enum RampOperationalStatus: String, Codable, Hashable, Sendable {
    case open
    case temporarilyClosed
    case closed
    case undetermined

    var label: String {
        switch self {
        case .open: "Open"
        case .temporarilyClosed: "Temporarily closed"
        case .closed: "Closed"
        case .undetermined: "Operating status unknown"
        }
    }
}

enum RampFacilityType: String, Codable, Hashable, Sendable {
    case motorized
    case paddle
    case airboat
    case marina
    case unknown

    var label: String {
        switch self {
        case .motorized: "Trailer boat ramp"
        case .paddle: "Paddlecraft launch"
        case .airboat: "Airboat ramp"
        case .marina: "Public marina ramp"
        case .unknown: "Boat ramp"
        }
    }
}

enum RampCoordinateType: String, Codable, Hashable, Sendable {
    case physicalRamp
    case facilityEntrance
    case approximate

    var label: String {
        switch self {
        case .physicalRamp: "Pin marks the launch ramp"
        case .facilityEntrance: "Pin marks the facility entrance"
        case .approximate: "Pin location is approximate"
        }
    }
}

enum SpotKind: String, Codable, Hashable, Sendable, CaseIterable {
    case ramp

    /// Retained for decoding legacy cached and favourited data only. Piers are no longer
    /// ingested by any provider and are filtered out before display. Do NOT delete this
    /// case: `MapSpot` is `Codable` and persisted by `MapDiskCache`, so removing it would
    /// break decoding of data written by earlier builds.
    case pier

    case weatherSpot

    var glyph: String {
        switch self {
        case .ramp: "ferry.fill"
        case .pier: "figure.fishing"
        case .weatherSpot: "cloud.sun.fill"
        }
    }

    var label: String {
        switch self {
        case .ramp: "Boat ramp"
        case .pier: "Fishing pier"
        case .weatherSpot: "Weather spot"
        }
    }
}

struct MapSpot: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let kind: SpotKind
    let provider: String?
    let details: [String: String]?
    let canonicalID: String?
    let sourceID: String?
    let sourceURL: String?
    let verificationLevel: RampVerificationLevel?
    let accessType: RampAccessType?
    let operationalStatus: RampOperationalStatus?
    let facilityType: RampFacilityType?
    let coordinateType: RampCoordinateType?
    let lastVerifiedAt: Date?
    let aliases: [String]?
    let navigationLatitude: Double?
    let navigationLongitude: Double?

    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        kind: SpotKind,
        provider: String? = nil,
        details: [String: String]? = nil,
        canonicalID: String? = nil,
        sourceID: String? = nil,
        sourceURL: String? = nil,
        verificationLevel: RampVerificationLevel? = nil,
        accessType: RampAccessType? = nil,
        operationalStatus: RampOperationalStatus? = nil,
        facilityType: RampFacilityType? = nil,
        coordinateType: RampCoordinateType? = nil,
        lastVerifiedAt: Date? = nil,
        aliases: [String]? = nil,
        navigationLatitude: Double? = nil,
        navigationLongitude: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
        self.provider = provider
        self.details = details
        self.canonicalID = canonicalID
        self.sourceID = sourceID
        self.sourceURL = sourceURL
        self.verificationLevel = verificationLevel
        self.accessType = accessType
        self.operationalStatus = operationalStatus
        self.facilityType = facilityType
        self.coordinateType = coordinateType
        self.lastVerifiedAt = lastVerifiedAt
        self.aliases = aliases
        self.navigationLatitude = navigationLatitude
        self.navigationLongitude = navigationLongitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var navigationCoordinate: CLLocationCoordinate2D? {
        guard let navigationLatitude, let navigationLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: navigationLatitude, longitude: navigationLongitude)
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
    case weatherSpots
    case marineStations
    case airports

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .ramps: "Boat ramps"
        case .weatherSpots: "Weather spots"
        case .marineStations: "Marine stations"
        case .airports: "Airports"
        }
    }

    func matches(_ spot: MapSpot) -> Bool {
        switch self {
        case .all: true
        case .ramps: spot.kind == .ramp
        case .weatherSpots: spot.kind == .weatherSpot
        case .marineStations, .airports: false
        }
    }
}

enum CuratedWeatherSpots {
    static let all: [MapSpot] = [
        MapSpot(
            id: "curated:gandy-bridge",
            name: "Gandy Bridge",
            latitude: 27.8936,
            longitude: -82.5415,
            kind: .weatherSpot,
            provider: "SeaSignal curated location",
            details: [
                "Area": "Old Tampa Bay",
                "Purpose": "Compare nearby modeled, airport, and marine observations",
                "Sensor note": "This pin marks a weather-interest location, not a dedicated weather sensor."
            ]
        )
    ]
}
