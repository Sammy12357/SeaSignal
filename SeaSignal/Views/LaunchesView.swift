import SwiftUI

struct LaunchesView: View {
    @State private var searchText = ""

    private var launches: [BoatLaunch] {
        searchText.isEmpty ? BoatLaunch.samples : BoatLaunch.samples.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.location.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(launches) { launch in
                        NavigationLink(value: launch) { LaunchCard(launch: launch) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(Color.mist.ignoresSafeArea())
            .navigationTitle("Boat launches")
            .searchable(text: $searchText, prompt: "Search launches or cities")
            .navigationDestination(for: BoatLaunch.self) { LaunchDetailView(launch: $0) }
        }
    }
}

