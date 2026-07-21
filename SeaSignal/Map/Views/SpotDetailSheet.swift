import SwiftUI

struct SpotDetailSheet: View {
    let spot: MapSpot
    @EnvironmentObject private var store: LaunchStore
    @Environment(\.dismiss) private var dismiss

    private var favorite: BoatLaunch? { store.favoriteLaunch(matching: spot) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: spot.kind.glyph)
                        .font(.title2)
                        .foregroundStyle(.oceanBlue)
                        .frame(width: 48, height: 48)
                        .background(Color.oceanBlue.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(spot.name).font(.title2.bold())
                        Text(spot.kind.label).foregroundStyle(.secondary)
                    }
                }

                if let favorite {
                    Label(favorite.summary, systemImage: "cloud.sun.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        LaunchDetailView(launch: favorite)
                    } label: {
                        Label("View boating conditions", systemImage: "wave.3.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.oceanBlue)
                    Button(role: .destructive) {
                        store.removeFavorite(matching: spot)
                        dismiss()
                    } label: {
                        Label("Remove from favorites", systemImage: "star.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text("Save this location to track its wind, waves, tides, and recommended launch window.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await store.addFavorite(from: spot) }
                    } label: {
                        Label("Add to favorites", systemImage: "star.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.oceanBlue)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Map location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
