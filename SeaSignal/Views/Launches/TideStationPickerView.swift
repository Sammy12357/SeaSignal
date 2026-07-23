import SwiftUI

struct TideStationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: LaunchStore
    let launch: BoatLaunch
    @State private var stations: [TideStation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        choose(nil)
                    } label: {
                        stationRow(name: "Automatic nearest station", selected: launch.tideStationID == nil)
                    }
                } footer: {
                    Text("Sea Signal normally uses the nearest NOAA prediction station within 40 km.")
                }

                Section("Nearby NOAA stations") {
                    if isLoading {
                        ProgressView("Loading stations…")
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary)
                    } else if stations.isEmpty {
                        Text("No NOAA prediction stations were found within 80 km.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(stations, id: \.id) { station in
                            Button { choose(station) } label: {
                                stationRow(name: station.name, selected: launch.tideStationID == station.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tide station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                do {
                    stations = try await NOAATideProvider.shared.nearbyStations(
                        latitude: launch.latitude,
                        longitude: launch.longitude
                    )
                } catch {
                    errorMessage = "Couldn’t load NOAA stations. Try again when you’re online."
                }
                isLoading = false
            }
        }
    }

    private func choose(_ station: TideStation?) {
        Task {
            await store.setTideStation(station, for: launch)
            dismiss()
        }
    }

    private func stationRow(name: String, selected: Bool) -> some View {
        HStack {
            Text(name).foregroundStyle(.primary)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(.oceanBlue) }
        }
    }
}

