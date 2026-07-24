import Foundation
import MapKit

@MainActor
final class MapTabViewModel: ObservableObject {
    @Published private(set) var spots: [MapSpot] = []
    @Published private(set) var windField: WindField?
    @Published private(set) var windObservations: [WindObservation] = []
    @Published private(set) var airportObservations: [AirportObservation] = []
    @Published private(set) var isLoadingSpots = false
    @Published private(set) var isLoadingWind = false
    @Published private(set) var isLoadingObservations = false
    @Published private(set) var spotStatusMessage: String?
    @Published private(set) var windStatusMessage: String?
    @Published private(set) var observationStatusMessage: String?
    @Published private(set) var airportStatusMessage: String?
    @Published private(set) var lastUpdated: Date?

    var statusMessage: String? { windStatusMessage ?? observationStatusMessage ?? airportStatusMessage ?? spotStatusMessage }
    var isLoadingMapData: Bool { isLoadingSpots || isLoadingWind || isLoadingObservations || isLoadingAirports }
    @Published private(set) var isLoadingAirports = false

    /// Clustering is a last-resort guard for continental-scale views only. At any zoom a
    /// boater would realistically use, every spot renders as an individual pin. Raise these
    /// values if clusters ever reappear at a usable scale; lower `clusterCountThreshold`
    /// (not the span) if dense regions start dropping frames.
    private static let clusterSpanThreshold: Double = 2.0
    private static let clusterCountThreshold: Int = 150

    private let overpass = OverpassProvider()
    private let windProvider = WindGridProvider()
    private let observationProvider = NOAAWindObservationProvider()
    private let airportProvider = AirportWeatherProvider()
    private let throttler = RegionThrottler()
    private var lastRegion: MKCoordinateRegion?
    private var lastSpotTile: MKCoordinateRegion?
    private var spotTask: Task<Void, Never>?
    private var windTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?
    private var airportTask: Task<Void, Never>?

    func regionSettled(
        _ region: MKCoordinateRegion,
        favorites: [MapSpot],
        offsetHours: Int,
        windLayerMode: WindLayerMode
    ) {
        lastRegion = region
        throttler.submit(region) { [weak self] region in
            self?.load(
                region: region,
                favorites: favorites,
                offsetHours: offsetHours,
                windLayerMode: windLayerMode
            )
        }
    }

    func refreshWind(offsetHours: Int, windLayerMode: WindLayerMode) {
        guard let lastRegion else { return }
        if windLayerMode.showsModeledWind {
            loadWind(region: lastRegion, offsetHours: offsetHours)
        }
    }

    func refreshWindLayer(windLayerMode: WindLayerMode, offsetHours: Int) {
        guard let lastRegion else { return }
        configureWindLayers(region: lastRegion, offsetHours: offsetHours, windLayerMode: windLayerMode)
    }

    func displayItems(filter: SpotFilter, favoritesOnly: Bool, favorites: [MapSpot], region: MKCoordinateRegion) -> [MapDisplayItem] {
        let merged = SpotDeduplicator.deduplicate(
            Self.merge(discovered: spots, favorites: favorites),
            isFavorite: { favorites.containsNear($0) }
        )
            // Piers are no longer ingested, but older builds may have cached or favourited
            // them. Drop them here so they disappear without breaking `Codable` decode.
            .filter { $0.kind != .pier }
            .filter(filter.matches)
            .filter { !favoritesOnly || favorites.containsNear($0) }
            .filter { GeoMath.contains(region, coordinate: $0.coordinate) }
        guard region.span.latitudeDelta > Self.clusterSpanThreshold
            || merged.count > Self.clusterCountThreshold else {
            return merged.map(MapDisplayItem.spot)
        }

        let cellLatitude = max(region.span.latitudeDelta / 6, 0.025)
        let cellLongitude = max(region.span.longitudeDelta / 4, 0.025)
        let grouped = Dictionary(grouping: merged) { spot in
            "\(Int((spot.latitude / cellLatitude).rounded(.down))):\(Int((spot.longitude / cellLongitude).rounded(.down)))"
        }
        return grouped.map { key, group in
            if group.count == 1 { return .spot(group[0]) }
            return .cluster(
                id: "cluster:\(key)",
                latitude: group.map(\.latitude).reduce(0, +) / Double(group.count),
                longitude: group.map(\.longitude).reduce(0, +) / Double(group.count),
                count: group.count
            )
        }
    }

    func coordinate(forSearch query: String, near region: MKCoordinateRegion) async -> CLLocationCoordinate2D? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = region
        return try? await MKLocalSearch(request: request).start().mapItems.first?.placemark.coordinate
    }

    static func merge(discovered: [MapSpot], favorites: [MapSpot]) -> [MapSpot] {
        favorites + discovered.filter { !favorites.containsNear($0) }
    }

    private func load(
        region: MKCoordinateRegion,
        favorites: [MapSpot],
        offsetHours: Int,
        windLayerMode: WindLayerMode
    ) {
        loadSpots(region: region, favorites: favorites)
        loadAirports(region: region)
        configureWindLayers(region: region, offsetHours: offsetHours, windLayerMode: windLayerMode)
    }

    private func configureWindLayers(
        region: MKCoordinateRegion,
        offsetHours: Int,
        windLayerMode: WindLayerMode
    ) {
        if windLayerMode.showsModeledWind {
            loadWind(region: region, offsetHours: offsetHours)
        } else {
            windTask?.cancel()
            windField = nil
            windStatusMessage = nil
            isLoadingWind = false
        }

        if windLayerMode.showsObservations {
            loadObservations(region: region)
        } else {
            observationTask?.cancel()
            windObservations = []
            observationStatusMessage = nil
            isLoadingObservations = false
        }
    }

    private func loadSpots(region: MKCoordinateRegion, favorites: [MapSpot]) {
        // Nothing to do if the quantised tile has not changed and we already have data.
        let tile = GeoMath.fetchTile(for: region)
        if let lastSpotTile, Self.sameTile(lastSpotTile, tile), !spots.isEmpty {
            return
        }

        spotTask?.cancel()
        guard region.span.latitudeDelta <= 3.2, region.span.longitudeDelta <= 3.2 else {
            // Keep whatever is already loaded on screen. displayItems already filters to the
            // visible region, so there is nothing to gain from discarding it — and discarding
            // it is what made zooming out and back in blank the map.
            spotStatusMessage = "Zoom in to discover more ramps"
            isLoadingSpots = false
            return
        }
        isLoadingSpots = true
        spotTask = Task {
            do {
                let result = try await overpass.fetch(in: region)
                guard !Task.isCancelled else { return }
                lastSpotTile = tile
                spots = Self.accumulate(
                    existing: spots,
                    found: result.spots,
                    favorites: favorites,
                    around: region.center
                )
                if result.wasTruncated {
                    spotStatusMessage = "Showing part of this area — zoom in for all ramps"
                } else {
                    spotStatusMessage = result.spots.isEmpty && spots.isEmpty
                        ? "No mapped ramps in this area"
                        : nil
                }
                lastUpdated = Date()
            } catch {
                guard !Task.isCancelled else { return }
                // Preserve existing spots; only report a problem if we have nothing to show.
                spotStatusMessage = spots.isEmpty ? "Ramp data is temporarily unavailable" : nil
            }
            isLoadingSpots = false
        }
    }

    /// Merges a freshly fetched tile into the running set instead of replacing it, so panning
    /// builds up coverage rather than thrashing. Bounded so a long session cannot grow forever.
    static func accumulate(
        existing: [MapSpot],
        found: [MapSpot],
        favorites: [MapSpot],
        around center: CLLocationCoordinate2D,
        limit: Int = 800
    ) -> [MapSpot] {
        let combined = SpotDeduplicator.deduplicate(existing + found + CuratedWeatherSpots.all)
        let bounded = combined.count <= limit
            ? combined
            : Array(combined.sorted {
                GeoMath.distance($0.coordinate, center) < GeoMath.distance($1.coordinate, center)
            }.prefix(limit))
        return merge(discovered: bounded, favorites: favorites)
    }

    private static func sameTile(_ lhs: MKCoordinateRegion, _ rhs: MKCoordinateRegion) -> Bool {
        abs(lhs.center.latitude - rhs.center.latitude) < 0.0001
            && abs(lhs.center.longitude - rhs.center.longitude) < 0.0001
            && abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) < 0.0001
    }

    private func loadAirports(region: MKCoordinateRegion) {
        airportTask?.cancel()
        guard region.span.latitudeDelta <= 8, region.span.longitudeDelta <= 8 else {
            airportObservations = []
            airportStatusMessage = "Zoom in to see airport observations"
            return
        }
        isLoadingAirports = true
        airportTask = Task {
            do {
                let snapshot = try await airportProvider.fetch(in: region)
                guard !Task.isCancelled else { return }
                airportObservations = snapshot.observations
                airportStatusMessage = snapshot.isStale ? "Showing saved airport observations" : nil
            } catch {
                guard !Task.isCancelled else { return }
                airportObservations = []
                airportStatusMessage = "Airport observations are temporarily unavailable"
            }
            isLoadingAirports = false
        }
    }

    private func loadWind(region: MKCoordinateRegion, offsetHours: Int) {
        windTask?.cancel()
        guard region.span.latitudeDelta <= 18, region.span.longitudeDelta <= 18 else {
            windField = nil
            return
        }
        isLoadingWind = true
        windTask = Task {
            do {
                let field = try await windProvider.fetch(in: region, offsetHours: offsetHours)
                guard !Task.isCancelled else { return }
                windField = field
                windStatusMessage = field.isStale ? "Offline — showing saved wind" : nil
                lastUpdated = field.fetchedAt
            } catch {
                guard !Task.isCancelled else { return }
                windStatusMessage = "Wind forecast is temporarily unavailable"
            }
            isLoadingWind = false
        }
    }

    private func loadObservations(region: MKCoordinateRegion) {
        observationTask?.cancel()
        guard region.span.latitudeDelta <= 18, region.span.longitudeDelta <= 18 else {
            windObservations = []
            observationStatusMessage = "Zoom in to see NOAA wind stations"
            isLoadingObservations = false
            return
        }

        isLoadingObservations = true
        observationTask = Task {
            do {
                let snapshot = try await observationProvider.fetch(in: region)
                guard !Task.isCancelled else { return }
                windObservations = snapshot.observations
                observationStatusMessage = snapshot.isStale ? "Offline — showing saved NOAA observations" : nil
                lastUpdated = snapshot.fetchedAt
            } catch {
                guard !Task.isCancelled else { return }
                windObservations = []
                observationStatusMessage = "NOAA station observations are temporarily unavailable"
            }
            isLoadingObservations = false
        }
    }
}

private extension Array where Element == MapSpot {
    func containsNear(_ spot: MapSpot) -> Bool {
        contains { GeoMath.distance($0.coordinate, spot.coordinate) < 50 }
    }
}
