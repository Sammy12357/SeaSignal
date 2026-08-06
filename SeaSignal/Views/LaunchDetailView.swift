import SwiftUI

struct LaunchDetailView: View {
    @EnvironmentObject private var store: LaunchStore
    let launch: BoatLaunch
    @State private var selectedTab: SpotDetailTab = .forecast
    @State private var showsTideStations = false
    private var displayedLaunch: BoatLaunch { store.launches.first(where: { $0.id == launch.id }) ?? launch }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SpotDetailTab.allCases) { tab in
                        Button(tab.rawValue) { selectedTab = tab }
                            .font(.subheadline.weight(selectedTab == tab ? .bold : .medium))
                            .foregroundStyle(selectedTab == tab ? Color.oceanBlue : .secondary)
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .overlay(alignment: .bottom) { if selectedTab == tab { Capsule().fill(Color.oceanBlue).frame(height: 3) } }
                    }
                }.padding(.horizontal, 10)
            }.background(Color.cardBackground)
            Group {
                switch selectedTab {
                case .forecast: ForecastTableView(launch: displayedLaunch)
                case .superforecast: ContentUnavailableView("Superforecast coming soon", systemImage: "waveform.path.ecg", description: Text("We’re evaluating higher-resolution sources before enabling this forecast."))
                case .webcams: ContentUnavailableView("No webcams yet", systemImage: "video.slash", description: Text("Camera feeds for this launch will appear here when available."))
                case .spotInfo: spotInfo
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.mist.ignoresSafeArea()).navigationTitle(displayedLaunch.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
            ShareLink(item: "SeaSignal forecast for \(displayedLaunch.name): \(displayedLaunch.summary)") { Image(systemName: "square.and.arrow.up") }
            Button { store.toggleFavorite(displayedLaunch) } label: { Image(systemName: store.isFavorite(displayedLaunch) ? "heart.fill" : "heart") }
        } }
        .sheet(isPresented: $showsTideStations) { TideStationPickerView(launch: displayedLaunch).environmentObject(store) }
    }

    private var spotInfo: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            Label(displayedLaunch.location, systemImage: "mappin.and.ellipse").font(.title3.bold())
            Text(displayedLaunch.distance + " away").foregroundStyle(.secondary)
            Text(displayedLaunch.summary)
            Divider(); Text("Tide source").font(.headline); Text(displayedLaunch.tideSource).foregroundStyle(.secondary)
            Button("Choose tide station") { showsTideStations = true }.buttonStyle(.bordered)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20) }
    }
}
