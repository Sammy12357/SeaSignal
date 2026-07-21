import CoreLocation
import MapKit
import SwiftUI

@MainActor
final class LaunchStore: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var launches: [BoatLaunch] = []
    @Published private(set) var favoriteIDs: Set<String> = []
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published private(set) var searchResultIDs: [String]? = nil

    private let locationManager = CLLocationManager()
    private let forecastService = MarineForecastService()
    private let defaults = UserDefaults.standard
    private var userLocation: CLLocation?
    private var hasAutoSelectedFavorites: Bool {
        get { defaults.bool(forKey: "hasAutoSelectedNearbyLaunches") }
        set { defaults.set(newValue, forKey: "hasAutoSelectedNearbyLaunches") }
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        favoriteIDs = Set(defaults.stringArray(forKey: "favoriteLaunchIDs") ?? [])
        if let data = defaults.data(forKey: "savedFavoriteLaunches"),
           let saved = try? JSONDecoder().decode([BoatLaunch].self, from: data) {
            launches = saved
        }
        authorizationStatus = locationManager.authorizationStatus
    }

    var favorites: [BoatLaunch] {
        launches.filter { favoriteIDs.contains($0.id) }
    }

    var filteredLaunches: [BoatLaunch] {
        if let searchResultIDs {
            let byID = Dictionary(uniqueKeysWithValues: launches.map { ($0.id, $0) })
            return searchResultIDs.compactMap { byID[$0] }
        }
        guard !searchText.isEmpty else { return launches }
        return launches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.location.localizedCaseInsensitiveContains(searchText)
        }
    }

    func start() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location access is off. Enable it in Settings or search for a ramp manually."
        @unknown default:
            break
        }
    }

    func search(at location: CLLocation? = nil) async {
        let center = location ?? userLocation
        guard let center else { return }
        isLoading = true
        errorMessage = nil

        do {
            let discovered = try await BoatLaunchSearchService.search(near: center)
            merge(discovered)
            if !hasAutoSelectedFavorites && favoriteIDs.isEmpty {
                favoriteIDs = Set(discovered.prefix(3).map(\.id))
                hasAutoSelectedFavorites = true
                saveFavorites()
            }
            isLoading = false
            await refreshForecasts()
        } catch {
            isLoading = false
            errorMessage = "Couldn’t find nearby boat ramps. Check your connection and try again."
        }
    }

    func searchByPlace() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResultIDs = nil
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let discovered = try await BoatLaunchSearchService.search(query: query, near: userLocation)
            merge(discovered)
            searchResultIDs = discovered.map(\.id)
            if discovered.isEmpty {
                errorMessage = "No boat ramps were found for “\(query)”. Try a nearby city or ramp name."
            }
            isLoading = false
            await refreshForecasts(ids: Set(discovered.map(\.id)))
        } catch {
            isLoading = false
            searchResultIDs = []
            errorMessage = "Couldn’t search Apple Maps for “\(query)”. Check your connection and try again."
        }
    }

    func clearPlaceSearch() {
        searchResultIDs = nil
        errorMessage = nil
    }

    func refreshForecasts(ids: Set<String>? = nil) async {
        let maxWind = defaults.double(forKey: "maxWindSpeed").nonZero(or: 24)
        let maxGust = defaults.double(forKey: "maxGustSpeed").nonZero(or: 32)
        let maxWave = defaults.double(forKey: "maxWaveHeight").nonZero(or: 0.8)

        await withTaskGroup(of: (String, MarineForecast?).self) { group in
            for launch in launches where ids == nil || ids!.contains(launch.id) {
                group.addTask { [forecastService] in
                    let result = try? await forecastService.forecast(
                        latitude: launch.latitude,
                        longitude: launch.longitude,
                        maxWind: maxWind,
                        maxGust: maxGust,
                        maxWave: maxWave
                    )
                    return (launch.id, result)
                }
            }

            for await (id, forecast) in group {
                guard let index = launches.firstIndex(where: { $0.id == id }) else { continue }
                guard let forecast else {
                    launches[index].conditions = .caution
                    launches[index].summary = "Live marine forecast is unavailable for this location."
                    launches[index].launchTime = "Unavailable"
                    launches[index].retrievalTime = "Unavailable"
                    launches[index].highTide = "Unavailable"
                    launches[index].lowTide = "Unavailable"
                    launches[index].tideSource = "No tide source available"
                    continue
                }
                launches[index].conditions = forecast.conditions
                launches[index].launchTime = forecast.launchTime
                launches[index].retrievalTime = forecast.retrievalTime
                launches[index].highTide = forecast.highTide
                launches[index].lowTide = forecast.lowTide
                launches[index].tideSource = forecast.tideSource
                launches[index].windSpeed = forecast.windSpeed
                launches[index].gustSpeed = forecast.gustSpeed
                launches[index].waveHeight = forecast.waveHeight
                launches[index].summary = forecast.summary
                launches[index].forecastUpdatedAt = forecast.updatedAt
            }
        }
        saveFavoriteLaunches()
    }

    func toggleFavorite(_ launch: BoatLaunch) {
        var updated = favoriteIDs
        if favoriteIDs.contains(launch.id) {
            updated.remove(launch.id)
        } else {
            updated.insert(launch.id)
        }
        withAnimation { favoriteIDs = updated }
        saveFavorites()
        saveFavoriteLaunches()
    }

    func isFavorite(_ launch: BoatLaunch) -> Bool {
        favoriteIDs.contains(launch.id)
    }

    private func saveFavorites() {
        defaults.set(Array(favoriteIDs), forKey: "favoriteLaunchIDs")
    }

    private func saveFavoriteLaunches() {
        let saved = launches.filter { favoriteIDs.contains($0.id) }
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: "savedFavoriteLaunches")
        }
    }

    private func merge(_ discovered: [BoatLaunch]) {
        var byID = Dictionary(uniqueKeysWithValues: launches.map { ($0.id, $0) })
        for launch in discovered {
            if let existing = byID[launch.id], existing.forecastUpdatedAt != nil {
                byID[launch.id] = existing
            } else {
                byID[launch.id] = launch
            }
        }
        let discoveredIDs = Set(discovered.map(\.id))
        let prefix = discovered.compactMap { byID[$0.id] }
        let remainder = launches.filter { !discoveredIDs.contains($0.id) }
        launches = prefix + remainder
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location
        Task { await search(at: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "Your location couldn’t be determined. Try again or search from the Launches tab."
    }
}

private extension Double {
    func nonZero(or fallback: Double) -> Double { self == 0 ? fallback : self }
}
