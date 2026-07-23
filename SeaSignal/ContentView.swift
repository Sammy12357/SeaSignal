import SwiftUI

struct ContentView: View {
    @StateObject private var launchStore = LaunchStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            MapTabView()
                .tabItem { Label("Map & Search", systemImage: "map.fill") }

            PreferencesView()
                .tabItem { Label("Preferences", systemImage: "slider.horizontal.3") }
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

#Preview {
    ContentView()
}
