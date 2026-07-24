import MapKit
import SwiftUI

private let defaultMapRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 27.95, longitude: -82.46),
    span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.25)
)

struct MapTabView: View {
    /// One full zoom level per tap. These must multiply to exactly 1.0 so that a zoom in
    /// followed by a zoom out returns to the original span; the previous 0.78 / 1.28 pair
    /// produced 0.998 and drifted slightly on every round trip.
    private static let zoomInScale: Double = 0.5
    private static let zoomOutScale: Double = 2.0

    @EnvironmentObject private var store: LaunchStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel = MapTabViewModel()
    @State private var position: MapCameraPosition = .region(defaultMapRegion)
    @State private var visibleRegion = defaultMapRegion
    @State private var selectedSpot: MapSpot?
    @State private var selectedWindObservation: WindObservation?
    @State private var selectedAirportObservation: AirportObservation?
    @State private var filter: SpotFilter = .all
    @State private var favoritesOnly = false
    @State private var showWind = true
    @State private var satellite = false
    @State private var showsMapSettings = false
    @State private var searchText = ""
    @State private var offsetHours = 0
    @State private var showsLaunchList = false
    @State private var centeredOnUser = false
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @AppStorage("mapWindDisplayMode") private var windDisplayModeRaw = WindDisplayMode.particleAnimation.rawValue
    @AppStorage("mapWindLayerMode") private var windLayerModeRaw = WindLayerMode.hybrid.rawValue
    @FocusState private var searchFocused: Bool

    var body: some View {
        MapReader { proxy in
            ZStack {
                baseMap
                    .mapAppearance(satellite: satellite)
                    .id(satellite)
                    .ignoresSafeArea(edges: .top)
                    .overlay {
                        ZStack {
                            windOverlays(proxy: proxy)
                            markerOverlay(proxy: proxy)
                        }
                    }
                    .onMapCameraChange(frequency: .continuous) { context in
                        visibleRegion = context.region
                        viewModel.regionSettled(
                            context.region,
                            favorites: store.favoriteMapSpots,
                            offsetHours: offsetHours,
                            windLayerMode: windLayerMode
                        )
                    }

                chrome
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showWind, windLayerMode.showsModeledWind {
                    ForecastTimelineBar(offsetHours: $offsetHours, validAt: viewModel.windField?.validAt)
                } else if showWind, windLayerMode.showsObservations {
                    observationStatusBar
                }
            }
        }
        .sheet(item: $selectedSpot) { SpotDetailSheet(spot: $0).environmentObject(store) }
        .sheet(item: $selectedWindObservation) { WindObservationDetailSheet(observation: $0) }
        .sheet(item: $selectedAirportObservation) { AirportObservationDetailSheet(observation: $0) }
        .sheet(isPresented: $showsLaunchList) { LaunchesView().environmentObject(store) }
        .sheet(isPresented: $showsMapSettings) {
            MapLayerSettingsSheet(
                showWind: $showWind,
                windLayerMode: windLayerModeBinding,
                windMode: windDisplayModeBinding,
                satellite: $satellite
            )
        }
        .onAppear {
            viewModel.regionSettled(
                visibleRegion,
                favorites: store.favoriteMapSpots,
                offsetHours: offsetHours,
                windLayerMode: windLayerMode
            )
            centerOnUserIfPossible()
        }
        .onChange(of: store.currentCoordinate?.latitude) { _, _ in centerOnUserIfPossible() }
        .onChange(of: offsetHours) { _, value in
            viewModel.refreshWind(offsetHours: value, windLayerMode: windLayerMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private func windOverlays(proxy: MapProxy) -> some View {
        if showWind, windLayerMode.showsModeledWind, let field = viewModel.windField {
            ZStack {
                WindColorOverlay(field: field, region: visibleRegion)
                if windDisplayMode == .movingArrows {
                    WindDirectionArrowOverlay(
                        field: field,
                        proxy: proxy,
                        lowPowerMode: lowPowerMode
                    )
                } else if windDisplayMode == .particleAnimation {
                    WindOverlay(
                        field: field,
                        region: visibleRegion,
                        mode: windDisplayMode,
                        isPaused: scenePhase != .active || reduceMotion,
                        lowPowerMode: lowPowerMode
                    )
                }
            }
        }
    }

    private var baseMap: some View {
        Map(position: $position, interactionModes: .all) {
            UserAnnotation()
            if showWind,
               windLayerMode.showsObservations,
               !favoritesOnly,
               offsetHours == 0,
               (filter == .all || filter == .marineStations) {
                ForEach(viewModel.windObservations) { observation in
                    Annotation("", coordinate: observation.coordinate, anchor: .center) {
                        Button {
                            selectedWindObservation = observation
                        } label: {
                            WindObservationPinView(observation: observation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !favoritesOnly,
               offsetHours == 0,
               (filter == .all || filter == .airports) {
                ForEach(viewModel.airportObservations) { observation in
                    Annotation("", coordinate: observation.coordinate, anchor: .center) {
                        Button {
                            selectedAirportObservation = observation
                        } label: {
                            AirportObservationPinView(observation: observation)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapControls { MapCompass(); MapScaleView() }
    }

    @ViewBuilder
    private func markerOverlay(proxy: MapProxy) -> some View {
        let items = viewModel.displayItems(
            filter: filter,
            favoritesOnly: favoritesOnly,
            favorites: store.favoriteMapSpots,
            region: visibleRegion
        )
        ForEach(items) { item in
            if let point = proxy.convert(item.coordinate, to: .local) {
                Button {
                    select(item)
                } label: {
                    switch item {
                    case .spot(let spot):
                        SpotPinView(spot: spot, isFavorite: store.isFavorite(spot))
                    // Continental-zoom fallback only; unreachable at normal boating scale.
                    case .cluster(_, _, _, let count):
                        ClusterPinView(count: count)
                    }
                }
                .buttonStyle(.plain)
                .position(x: point.x, y: point.y - 22)
            }
        }

    }

    private var chrome: some View {
        VStack(spacing: 0) {
            if showWind, windLayerMode.showsModeledWind {
                WindLegendView(sourceLabel: windLegendSource)
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    searchBar
                    MapFilterBar(
                        filter: $filter,
                        favoritesOnly: $favoritesOnly,
                        windLayerMode: windLayerModeBinding
                    )
                }
                Spacer(minLength: 0)
                mapButtons
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Spacer()
            mapFooter
        }
    }

    private var mapFooter: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.deepNavy)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
            Spacer(minLength: 0)
            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.deepNavy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
            } else if viewModel.isLoadingMapData {
                ProgressView()
                    .padding(9)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel("Updating map")
            } else if let updated = viewModel.lastUpdated {
                Text("Updated \(updated.formatted(.dateTime.hour().minute()))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.deepNavy)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(Color.deepNavy)
            TextField("Search city, ramp, pier, airport, or weather spot", text: $searchText)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { performSearch() }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.deepNavy.opacity(0.1)))
        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
        .frame(maxWidth: 310)
    }

    private var mapButtons: some View {
        VStack(spacing: 10) {
            controlButton(icon: showWind ? "wind" : "wind.snow", label: "Wind layer") { showWind.toggle() }
            controlButton(icon: "location.fill", label: "My location") { centerOnUser(force: true) }
            controlButton(icon: "map.fill", label: "Map settings") { showsMapSettings = true }
            controlButton(icon: "list.bullet", label: "Launch list") { showsLaunchList = true }
            controlButton(icon: "plus.magnifyingglass", label: "Zoom in") { zoomMap(by: Self.zoomInScale) }
            controlButton(icon: "minus.magnifyingglass", label: "Zoom out") { zoomMap(by: Self.zoomOutScale) }
        }
    }

    private func controlButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.deepNavy)
                .frame(width: 46, height: 46)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.deepNavy.opacity(0.1)))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func performSearch() {
        let query = searchText
        searchFocused = false
        Task {
            guard let coordinate = await viewModel.coordinate(forSearch: query, near: visibleRegion) else { return }
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.32, longitudeDelta: 0.32)
                ))
            }
        }
    }

    private func select(_ item: MapDisplayItem) {
        switch item {
        case .spot(let spot):
            selectedSpot = spot
        // Continental-zoom fallback only; see MapTabViewModel.clusterSpanThreshold.
        case .cluster(_, let latitude, let longitude, _):
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(
                        latitudeDelta: max(visibleRegion.span.latitudeDelta / 2.5, 0.02),
                        longitudeDelta: max(visibleRegion.span.longitudeDelta / 2.5, 0.02)
                    )
                ))
            }
        }
    }

    private func centerOnUserIfPossible() {
        guard !centeredOnUser else { return }
        centerOnUser(force: false)
    }

    private var windDisplayMode: WindDisplayMode {
        WindDisplayMode(rawValue: windDisplayModeRaw) ?? .particleAnimation
    }

    private var windDisplayModeBinding: Binding<WindDisplayMode> {
        Binding(
            get: { windDisplayMode },
            set: { windDisplayModeRaw = $0.rawValue }
        )
    }

    private var windLayerMode: WindLayerMode {
        WindLayerMode(rawValue: windLayerModeRaw) ?? .hybrid
    }

    private var windLayerModeBinding: Binding<WindLayerMode> {
        Binding(
            get: { windLayerMode },
            set: { setWindLayerMode($0) }
        )
    }

    private func setWindLayerMode(_ mode: WindLayerMode) {
        guard mode != windLayerMode else { return }
        showWind = true
        windLayerModeRaw = mode.rawValue
        if !mode.showsModeledWind { offsetHours = 0 }
        viewModel.refreshWindLayer(windLayerMode: mode, offsetHours: offsetHours)
    }

    private var windLegendSource: String {
        if windLayerMode == .hybrid, offsetHours == 0 {
            return "Hybrid · \(viewModel.windObservations.count) marine · \(viewModel.airportObservations.count) airport"
        }
        return "Modeled surface · 10 m"
    }

    private var observationStatusBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LIVE OBSERVATIONS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.oceanBlue)
                Text("\(viewModel.windObservations.count) marine · \(viewModel.airportObservations.count) airport")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.deepNavy)
            }
            Spacer()
            Label("Current", systemImage: "dot.radiowaves.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.deepNavy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func centerOnUser(force: Bool) {
        guard let coordinate = store.currentCoordinate else {
            if force { store.start() }
            return
        }
        centeredOnUser = true
        withAnimation {
            position = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.30, longitudeDelta: 0.25)
            ))
        }
    }

    private func zoomMap(by scale: Double) {
        let region = GeoMath.zoomedRegion(visibleRegion, scale: scale)
        visibleRegion = region
        guard !reduceMotion else {
            position = .region(region)
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            position = .region(region)
        }
    }
}

private extension View {
    @ViewBuilder
    func mapAppearance(satellite: Bool) -> some View {
        if satellite {
            mapStyle(.hybrid(elevation: .flat))
        } else {
            mapStyle(.standard(elevation: .flat))
        }
    }
}
