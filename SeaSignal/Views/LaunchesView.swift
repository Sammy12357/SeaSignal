import SwiftUI
import MapKit

struct LaunchesView: View {
    private enum DisplayMode: String, CaseIterable {
        case map = "Map"
        case list = "List"
    }

    private enum WeatherLayer: String, CaseIterable {
        case wind = "Wind"
        case waves = "Waves"
        case currents = "Currents"

        var icon: String {
            switch self {
            case .wind: "wind"
            case .waves: "water.waves"
            case .currents: "arrow.triangle.2.circlepath"
            }
        }
    }

    @StateObject private var weather = WeatherMapViewModel()
    @State private var searchText = ""
    @State private var displayMode: DisplayMode = .map
    @State private var navigationPath: [BoatLaunch] = []
    @State private var isPlayingForecast = false
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 43.63, longitude: -79.40),
            span: MKCoordinateSpan(latitudeDelta: 0.72, longitudeDelta: 1.05)
        )
    )
    @AppStorage("weatherEffectsEnabled") private var effectsEnabled = true
    @AppStorage("weatherEffectsLayer") private var storedLayer = "wind"

    private var selectedLayer: WeatherLayer {
        get { WeatherLayer(rawValue: storedLayer.capitalized) ?? .wind }
        nonmutating set { storedLayer = newValue.rawValue.lowercased() }
    }

    private var launches: [BoatLaunch] {
        searchText.isEmpty ? BoatLaunch.samples : BoatLaunch.samples.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.location.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if displayMode == .map {
                    mapContent
                } else {
                    listContent
                }
            }
            .navigationTitle("Boat launches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Display", selection: $displayMode) {
                        ForEach(DisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 145)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        weather.refresh()
                    } label: {
                        if weather.state == .loading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh forecast")
                }
            }
            .searchable(text: $searchText, prompt: "Search launches or cities")
            .navigationDestination(for: BoatLaunch.self) { launch in
                LaunchDetailView(launch: launch)
            }
        }
        .task { weather.load() }
        .task(id: isPlayingForecast) {
            guard isPlayingForecast else { return }
            while !Task.isCancelled && isPlayingForecast {
                try? await Task.sleep(for: .seconds(1.4))
                guard !weather.availableTimes.isEmpty else { continue }
                weather.selectedTimeIndex = (weather.selectedTimeIndex + 1) % weather.availableTimes.count
            }
        }
    }

    private var mapContent: some View {
        MapReader { proxy in
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition) {
                    ForEach(launches) { launch in
                        Annotation(launch.name, coordinate: launch.coordinate, anchor: .bottom) {
                            Button {
                                navigationPath.append(launch)
                            } label: {
                                VStack(spacing: 3) {
                                    if let sample = weather.forecast(for: launch), effectsEnabled, selectedLayer == .wind {
                                        WindArrowView(sample: sample, animated: true)
                                    }
                                    LaunchMapMarker(launch: launch)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }

                if effectsEnabled, selectedLayer == .wind, let field = weather.selectedWindField {
                    WindParticleCanvas(
                        field: field,
                        project: { proxy.convert($0, to: .local) },
                        isEnabled: true
                    )
                }

                mapControls
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(launches) { launch in
                    Button {
                        navigationPath.append(launch)
                    } label: {
                        LaunchCard(launch: launch)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(Color.mist.ignoresSafeArea())
    }

    private var mapControls: some View {
        VStack(spacing: 10) {
            forecastStatus

            HStack(spacing: 8) {
                ForEach(WeatherLayer.allCases, id: \.self) { layer in
                    Button {
                        selectedLayer = layer
                    } label: {
                        Label(layer.rawValue, systemImage: layer.icon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .foregroundStyle(selectedLayer == layer ? .white : .deepNavy)
                            .background(
                                selectedLayer == layer ? Color.oceanBlue : Color.white.opacity(0.9),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    effectsEnabled.toggle()
                } label: {
                    Image(systemName: effectsEnabled ? "eye.fill" : "eye.slash.fill")
                        .frame(width: 34, height: 34)
                        .foregroundStyle(.deepNavy)
                        .background(.white.opacity(0.9), in: Circle())
                }
                .accessibilityLabel(effectsEnabled ? "Hide effects" : "Show effects")
            }

            if !weather.availableTimes.isEmpty {
                VStack(spacing: 5) {
                    HStack {
                        Button {
                            isPlayingForecast.toggle()
                        } label: {
                            Label(
                                isPlayingForecast ? "Pause" : "Play",
                                systemImage: isPlayingForecast ? "pause.fill" : "play.fill"
                            )
                            .font(.caption.weight(.bold))
                        }
                        Spacer()
                        Text(weather.selectedTime?.formatted(date: .abbreviated, time: .shortened) ?? "")
                            .font(.caption.monospacedDigit())
                    }
                    Slider(
                        value: Binding(
                            get: { Double(weather.selectedTimeIndex) },
                            set: { weather.selectedTimeIndex = Int($0.rounded()) }
                        ),
                        in: 0...Double(max(weather.availableTimes.count - 1, 1)),
                        step: 1
                    )
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                Circle().fill(.cyan).frame(width: 7, height: 7)
                Text(selectedLayer == .wind ? "Particles show wind travel direction" : "\(selectedLayer.rawValue) overlay is awaiting available marine coverage")
                Spacer()
                Text("Open-Meteo")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var forecastStatus: some View {
        switch weather.state {
        case .idle:
            EmptyView()
        case .loading:
            Label("Loading live marine forecast…", systemImage: "arrow.triangle.2.circlepath")
                .statusPill()
        case .live:
            Label("Live forecast", systemImage: "checkmark.circle.fill")
                .statusPill(color: .seaGreen)
        case .stale(let message):
            Label(message, systemImage: "clock.badge.exclamationmark")
                .statusPill(color: .warningOrange)
        case .sample(let message):
            Label(message, systemImage: "wifi.slash")
                .lineLimit(2)
                .statusPill(color: .warningOrange)
        }
    }
}

private struct LaunchMapMarker: View {
    let launch: BoatLaunch

    private var color: Color {
        switch launch.conditions {
        case .ideal: .seaGreen
        case .caution: .warningOrange
        case .avoid: .dangerRed
        }
    }

    var body: some View {
        Image(systemName: "sailboat.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .accessibilityLabel("\(launch.name), \(launch.conditions.rawValue) conditions")
    }
}

private extension View {
    func statusPill(color: Color = .oceanBlue) -> some View {
        self
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
