import SwiftUI

struct LaunchesView: View {
    @EnvironmentObject private var store: LaunchStore
    @State private var showsPinDrop = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let message = store.errorMessage {
                        Text(message).font(.subheadline).foregroundStyle(.secondary).padding()
                    }
                    if store.isLoading {
                        ProgressView("Searching boat ramps…").padding()
                    }
                    ForEach(store.filteredLaunches) { launch in
                        HStack(spacing: 10) {
                            NavigationLink(value: launch) { LaunchCard(launch: launch) }
                                .buttonStyle(.plain)
                            Button {
                                store.toggleFavorite(launch)
                            } label: {
                                Image(systemName: store.isFavorite(launch) ? "heart.fill" : "heart")
                                    .font(.title3)
                                    .foregroundStyle(.oceanBlue)
                                    .frame(width: 46, height: 46)
                                    .background(.white, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(store.isFavorite(launch) ? "Remove favorite" : "Add favorite")
                        }
                    }
                }
                .padding(18)
            }
            .background(Color.mist.ignoresSafeArea())
            .navigationTitle("Boat launches")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsPinDrop = true } label: {
                        Label("Pin launch", systemImage: "mappin.and.ellipse")
                    }
                }
            }
            .searchable(text: $store.searchText, prompt: "Search city or boat ramp")
            .onSubmit(of: .search) {
                Task { await store.searchByPlace() }
            }
            .onChange(of: store.searchText) { _, value in
                if value.isEmpty { store.clearPlaceSearch() }
            }
            .refreshable { await store.search() }
            .navigationDestination(for: BoatLaunch.self) { LaunchDetailView(launch: $0) }
            .sheet(isPresented: $showsPinDrop) {
                AddLaunchMapView().environmentObject(store)
            }
        }
    }
}
