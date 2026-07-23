import Foundation
import MapKit

@MainActor
final class MapTabViewModel: ObservableObject {
    @Published private(set) var spots: [MapSpot] = []
    @Published private(set) var windField: WindField?
    @Published private(set) var windObservations: [WindObservation] = []
    @Published private(set) var isLoadingSpots = false
    @Published private(set) var isLoadingWind = false
    @Published private(set) var isLoadingObservations = false
    @Published private(set) var spotStatusMessage: String?
    @Published private(set) var windStatusMessage: String?
    @Published private(set) var observationStatusMessage: String?
    @Published private(set) var lastUpdated: Date?

    var statusMessage: String? { windStatusMessage ?? observationStatusMessage ?? spotStatusMessage }
    var isLoadingMapData: Bool { isLoadingSpots || isLoadingWind || isLoadingObservations }

    private let overpass = OverpassProvider()
    private let windProvider = WindGridProvider()
    private let observationProvider = NOAAWindObservationProvider()
    private let throttler = RegionThrottler()
    private var lastRegion: MKCoordinateRegion?
    private var spotTask: Task<Void, Never>?
    private var windTask: Task<Void, Never>?
    private var observationTask: Task<Void, Never>?

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
        let merged = Self.merge(discovered: spots, favorites: favorites)
            .filter(filter.matches)
            .filter { !favoritesOnly || favorites.containsNear($0) }
            .filter { GeoMath.contains(region, coordinate: $0.coordinate) }
        guard region.span.latitudeDelta > 0.18 || merged.count > 70 else {
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
        spotTask?.cancel()
        guard region.span.latitudeDelta <= 3.2, region.span.longitudeDelta <= 3.2 else {
            spots = []
            spotStatusMessage = "Zoom in to discover ramps and piers"
            return
        }
        isLoadingSpots = true
        spotTask = Task {
            do {
                let found = try await overpass.fetch(in: region)
                guard !Task.isCancelled else { return }
                spots = Self.merge(discovered: found, favorites: favorites)
                spotStatusMessage = found.isEmpty ? "No mapped ramps or piers in this area" : nil
                lastUpdated = Date()
            } catch {
                guard !Task.isCancelled else { return }
                spotStatusMessage = "Ramp data is temporarily unavailable"
            }
            isLoadingSpots = false
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
