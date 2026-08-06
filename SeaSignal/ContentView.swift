import SwiftUI

struct ContentView: View {
    @StateObject private var launchStore = LaunchStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Favorites", systemImage: "star.fill") }

            MapTabView()
                .tabItem { Label("Map & Search", systemImage: "map.fill") }

            NavigationStack {
                ContentUnavailableView("No alerts", systemImage: "bell", description: Text("Weather and safety alerts for favorite launches will appear here."))
                    .navigationTitle("Alerts")
            }
            .tabItem { Label("Alerts", systemImage: "bell") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .environmentObject(launchStore)
        .task { launchStore.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await launchStore.refreshForecasts(ids: Set(launchStore.favorites.map(\.id))) }
            }
        }
    }
}

private struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { LaunchesView() } label: { Label("Manage launches", systemImage: "sailboat") }
                NavigationLink { PreferencesView() } label: { Label("Safety preferences", systemImage: "slider.horizontal.3") }
                Section("About") { LabeledContent("Forecast sources", value: "Open-Meteo + NOAA") }
            }
            .navigationTitle("More")
        }
    }
}

#Preview {
    ContentView()
}
