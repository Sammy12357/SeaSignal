import Foundation

/// Single source of truth for collapsing near-duplicate map pins.
///
/// Previously three separate proximity passes existed (35 m inside `OverpassProvider`,
/// 75 m inside the MapKit fallback, 50 m for favourites) and none of them considered
/// `SpotKind`, so when two markers described the same physical place the survivor was
/// effectively arbitrary. Everything now funnels through this type.
enum SpotDeduplicator {
    /// The requested 1,000-foot duplicate search radius. Identity and compatible-name
    /// checks below still prevent proximity alone from collapsing separately named ramps.
    static let radiusMetres: Double = 304.8

    /// Collapses records that describe the same facility and fall within `radiusMetres`.
    /// Proximity alone is deliberately insufficient: two named, independently identified
    /// ramps can legitimately sit next to one another in a marina or park.
    ///
    /// Survivor precedence, in order:
    /// 1. Favourite over non-favourite — a saved launch is never replaced by a discovered pin.
    /// 2. Kind: `.ramp` > `.weatherSpot` > `.pier`.
    /// 3. Named over generic.
    /// 4. Provider: OpenStreetMap over Apple Maps.
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
                shouldMerge($0, spot, radiusMetres: radiusMetres, isFavorite: isFavorite)
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
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "public boat ramp"
            || normalized == "boat launch"
            || normalized == "boat ramp"
            || normalized == "fishing pier"
    }

    static func namesReferToSameFacility(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedName(lhs)
        let right = normalizedName(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        let union = leftTokens.union(rightTokens)
        guard !union.isEmpty else { return false }
        return Double(leftTokens.intersection(rightTokens).count) / Double(union.count) >= 0.8
    }

    private static func shouldMerge(
        _ lhs: MapSpot,
        _ rhs: MapSpot,
        radiusMetres: Double,
        isFavorite: (MapSpot) -> Bool
    ) -> Bool {
        if lhs.id == rhs.id { return true }
        if let left = lhs.canonicalID, let right = rhs.canonicalID {
            return left == right
        }
        if let left = lhs.sourceID, let right = rhs.sourceID, lhs.provider == rhs.provider {
            return left == right
        }
        guard GeoMath.distance(lhs.coordinate, rhs.coordinate) < radiusMetres else { return false }

        // Weather-interest locations and launch facilities are separate map concepts even
        // when they intentionally share a shoreline coordinate.
        if lhs.kind == .weatherSpot || rhs.kind == .weatherSpot {
            return lhs.kind == rhs.kind && namesReferToSameFacility(lhs.name, rhs.name)
        }

        // Never collapse two distinct official records merely because their ramps are close.
        if lhs.verificationLevel == .official, rhs.verificationLevel == .official {
            return false
        }
        if isFavorite(lhs) || isFavorite(rhs) { return true }
        if isGenericName(lhs.name) || isGenericName(rhs.name) { return true }
        if lhs.kind != rhs.kind { return true }
        return namesReferToSameFacility(lhs.name, rhs.name)
    }

    private static func normalizedName(_ value: String) -> String {
        let ignored: Set<String> = [
            "boat", "boating", "public", "ramp", "ramps", "launch", "landing",
            "park", "regional", "conservation", "facility", "access"
        ]
        return value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !ignored.contains($0) }
            .map { token in
                token.count > 4 && token.hasSuffix("s") ? String(token.dropLast()) : token
            }
            .joined(separator: " ")
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

        let lhsVerification = rank(verification: lhs.verificationLevel)
        let rhsVerification = rank(verification: rhs.verificationLevel)
        if lhsVerification != rhsVerification { return lhsVerification > rhsVerification ? lhs : rhs }

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
        case "Florida FWC": 4
        case "SeaSignal verified catalog": 3
        case "OpenStreetMap": 2
        case "Apple Maps": 0
        default: 1
        }
    }

    private static func rank(verification: RampVerificationLevel?) -> Int {
        switch verification {
        case .official: 4
        case .verified: 3
        case .communityConfirmed: 2
        case .unverified: 1
        case nil: 0
        }
    }

    private static func merging(_ survivor: MapSpot, with discarded: MapSpot) -> MapSpot {
        var merged = survivor.details ?? [:]
        for (key, value) in discarded.details ?? [:] where merged[key] == nil {
            merged[key] = value
        }
        return MapSpot(
            id: survivor.id,
            name: survivor.name,
            latitude: survivor.latitude,
            longitude: survivor.longitude,
            kind: survivor.kind,
            provider: survivor.provider,
            details: merged.isEmpty ? nil : merged,
            canonicalID: survivor.canonicalID ?? discarded.canonicalID,
            sourceID: survivor.sourceID ?? discarded.sourceID,
            sourceURL: survivor.sourceURL ?? discarded.sourceURL,
            verificationLevel: survivor.verificationLevel ?? discarded.verificationLevel,
            accessType: survivor.accessType ?? discarded.accessType,
            operationalStatus: survivor.operationalStatus ?? discarded.operationalStatus,
            facilityType: survivor.facilityType ?? discarded.facilityType,
            coordinateType: survivor.coordinateType ?? discarded.coordinateType,
            lastVerifiedAt: survivor.lastVerifiedAt ?? discarded.lastVerifiedAt,
            aliases: mergedAliases(survivor, discarded),
            navigationLatitude: survivor.navigationLatitude ?? discarded.navigationLatitude,
            navigationLongitude: survivor.navigationLongitude ?? discarded.navigationLongitude
        )
    }

    private static func mergedAliases(_ survivor: MapSpot, _ discarded: MapSpot) -> [String]? {
        let values = Set((survivor.aliases ?? []) + (discarded.aliases ?? []) + [discarded.name])
            .filter { $0 != survivor.name }
        return values.isEmpty ? nil : values.sorted()
    }
}
