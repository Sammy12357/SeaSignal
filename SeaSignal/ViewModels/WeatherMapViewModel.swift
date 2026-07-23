import Foundation
import CoreLocation
import Combine

@MainActor
final class WeatherMapViewModel: ObservableObject {
    enum LoadingState: Equatable {
        case idle
        case loading
        case live
        case stale(String)
        case sample(String)
    }

    @Published private(set) var forecastsByLaunch: [String: [WindSample]] = [:]
    @Published private(set) var fieldForecasts: [[WindSample]] = []
    @Published private(set) var availableTimes: [Date] = []
    @Published var selectedTimeIndex = 0
    @Published private(set) var state: LoadingState = .idle

    private let service: any WeatherService
    private let fallbackService: any WeatherService
    private let cache: ForecastCache
    private var loadTask: Task<Void, Never>?

    init(
        service: any WeatherService = OpenMeteoWeatherService(),
        fallbackService: any WeatherService = SampleWeatherService(),
        cache: ForecastCache = ForecastCache()
    ) {
        self.service = service
        self.fallbackService = fallbackService
        self.cache = cache
    }

    deinit {
        loadTask?.cancel()
    }

    var selectedTime: Date? {
        availableTimes[safe: selectedTimeIndex]
    }

    var selectedWindField: WindField? {
        guard let time = selectedTime else { return nil }
        let samples = fieldForecasts.compactMap { nearestSample(in: $0, to: time) }
        return samples.isEmpty ? nil : WindField(samples: samples, timestamp: time)
    }

    func forecast(for launch: BoatLaunch) -> WindSample? {
        guard let values = forecastsByLaunch[launch.id], let time = selectedTime else {
            return nil
        }
        return nearestSample(in: values, to: time)
    }

    func load() {
        guard state != .loading else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad()
        }
    }

    func refresh() {
        loadTask?.cancel()
        state = .idle
        load()
    }

    private func performLoad() async {
        state = .loading
        let launches = BoatLaunch.samples
        do {
            var launchResults: [String: [WindSample]] = [:]
            for launch in launches {
                try Task.checkCancellation()
                let values = try await loadForecast(at: launch.coordinate)
                launchResults[launch.id] = values
            }

            forecastsByLaunch = launchResults
            fieldForecasts = Array(launchResults.values)
            availableTimes = launchResults.values.first?.map(\.timestamp) ?? []
            selectedTimeIndex = nearestTimeIndex(to: Date())
            state = .live
        } catch is CancellationError {
            return
        } catch {
            await loadFallback(reason: error.localizedDescription)
        }
    }

    private func loadForecast(at coordinate: CLLocationCoordinate2D) async throws -> [WindSample] {
        if let cached = await cache.samples(for: coordinate) {
            return cached
        }
        do {
            let values = try await service.windForecast(at: coordinate)
            await cache.store(values, for: coordinate)
            return values
        } catch {
            if let stale = await cache.samples(for: coordinate, allowStale: true) {
                state = .stale("Showing cached forecast")
                return stale
            }
            throw error
        }
    }

    private func loadFallback(reason: String) async {
        var launchResults: [String: [WindSample]] = [:]
        for launch in BoatLaunch.samples {
            launchResults[launch.id] = try? await fallbackService.windForecast(at: launch.coordinate)
        }
        forecastsByLaunch = launchResults
        fieldForecasts = Array(launchResults.values)
        availableTimes = launchResults.values.first?.map(\.timestamp) ?? []
        selectedTimeIndex = nearestTimeIndex(to: Date())
        state = .sample("Live forecast unavailable: \(reason)")
    }

    private func nearestSample(in values: [WindSample], to time: Date) -> WindSample? {
        values.min { abs($0.timestamp.timeIntervalSince(time)) < abs($1.timestamp.timeIntervalSince(time)) }
    }

    private func nearestTimeIndex(to time: Date) -> Int {
        availableTimes.enumerated().min {
            abs($0.element.timeIntervalSince(time)) < abs($1.element.timeIntervalSince(time))
        }?.offset ?? 0
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
