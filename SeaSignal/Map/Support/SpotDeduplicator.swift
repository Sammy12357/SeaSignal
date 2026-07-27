import Foundation

/// Single source of truth for collapsing near-duplicate map pins.
///
/// Previously three separate proximity passes existed (35 m inside `OverpassProvider`,
/// 75 m inside the MapKit fallback, 50 m for favourites) and none of them considered
/// `SpotKind`, so when two markers described the same physical place the survivor was
/// effectively arbitrary. Everything now funnels through this type.
enum SpotDeduplicator {
    /// Product rule: locations within 1,000 feet represent the same launch. Keeping the
    /// conversion here makes every provider and favorite merge use the exact same radius.
    static let radiusMetres: Double = 1_000 * 0.3048

    /// Collapses spots that fall within `radiusMetres` of one another.
    ///
    /// Survivor precedence, in order:
    /// 1. Favourite over non-favourite — a saved launch is never replaced by a discovered pin.
    /// 2. Kind: `.ramp` > `.weatherSpot` > `.pier`.
    /// 3. Named over generic.
    /// 4. Provider: OpenStreetMap over Apple Maps when names are equally useful.
    /// 5. Lowest `id` lexicographically, so repeated runs do not flicker.
    ///
    /// `details` from the discarded spot are merged into the survivor wherever the
    /// survivor has no value for that key, so no information is lost.
    static func deduplicate(
        _ spots: [MapSpot],
        radiusMetres: Double = SpotDeduplicator.radiusMetres,
        isFavorite: (MapSpot) -> Bool = { _ in false }
    ) -> [MapSpot] {
        // Sorting first makes the output order independent of provider response order.
        var result: [MapSpot] = []
        for spot in spots.sorted(by: { $0.id < $1.id }) {
            guard let index = result.firstIndex(where: {
                canRepresentSamePlace($0, spot)
                    && GeoMath.distance($0.coordinate, spot.coordinate) < radiusMetres
            }) else {
                result.append(spot)
                continue
            }
            let existing = result[index]
            let survivor = preferred(existing, spot, isFavorite: isFavorite)
            let discarded = survivor.id == existing.id ? spot : existing
            result[index] = merging(survivor, with: discarded)
        }
        return result
    }

    static func isGenericName(_ name: String) -> Bool {
        name == "Public boat ramp" || name == "Fishing pier"
    }

    /// A nearby weather-interest marker is not a duplicate of a launch. Legacy pier pins
    /// can still collapse into ramps so old persisted data does not create double markers.
    private static func canRepresentSamePlace(_ lhs: MapSpot, _ rhs: MapSpot) -> Bool {
        if lhs.kind == .weatherSpot || rhs.kind == .weatherSpot {
            return lhs.kind == rhs.kind
        }
        return true
    }

    // MARK: - Precedence

    private static func preferred(
        _ lhs: MapSpot,
        _ rhs: MapSpot,
        isFavorite: (MapSpot) -> Bool
    ) -> MapSpot {
        let lhsFavorite = isFavorite(lhs)
        let rhsFavorite = isFavorite(rhs)
        if lhsFavorite != rhsFavorite { return lhsFavorite ? lhs : rhs }

        let lhsKind = rank(lhs.kind)
        let rhsKind = rank(rhs.kind)
        if lhsKind != rhsKind { return lhsKind > rhsKind ? lhs : rhs }

        let lhsNamed = !isGenericName(lhs.name)
        let rhsNamed = !isGenericName(rhs.name)
        if lhsNamed != rhsNamed { return lhsNamed ? lhs : rhs }

        let lhsProvider = rank(provider: lhs.provider)
        let rhsProvider = rank(provider: rhs.provider)
        if lhsProvider != rhsProvider { return lhsProvider > rhsProvider ? lhs : rhs }

        return lhs.id <= rhs.id ? lhs : rhs
    }

    private static func rank(_ kind: SpotKind) -> Int {
        switch kind {
        case .ramp: 2
        case .weatherSpot: 1
        case .pier: 0
        }
    }

    private static func rank(provider: String?) -> Int {
        switch provider {
        case "OpenStreetMap": 2
        case "Apple Maps": 0
        default: 1
        }
    }

    private static func merging(_ survivor: MapSpot, with discarded: MapSpot) -> MapSpot {
        guard let extra = discarded.details, !extra.isEmpty else { return survivor }
        var merged = survivor.details ?? [:]
        for (key, value) in extra where merged[key] == nil {
            merged[key] = value
        }
        return MapSpot(
            id: survivor.id,
            name: survivor.name,
            latitude: survivor.latitude,
            longitude: survivor.longitude,
            kind: survivor.kind,
            provider: survivor.provider,
            details: merged
        )
    }
}
