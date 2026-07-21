import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            LaunchesView()
                .tabItem { Label("Launches", systemImage: "map.fill") }

            PreferencesView()
                .tabItem { Label("Preferences", systemImage: "slider.horizontal.3") }
        }
    }
}

#Preview {
    ContentView()
}

