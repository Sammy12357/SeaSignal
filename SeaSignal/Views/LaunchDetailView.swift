import SwiftUI

struct LaunchDetailView: View {
    @EnvironmentObject private var store: LaunchStore
    let launch: BoatLaunch

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ConditionBadge(conditions: launch.conditions)
                        Spacer()
                        Button { store.toggleFavorite(launch) } label: {
                            Image(systemName: store.isFavorite(launch) ? "heart.fill" : "heart")
                        }
                    }
                    Text(launch.name).font(.largeTitle.bold()).foregroundStyle(.deepNavy)
                    Label("\(launch.location) · \(launch.distance) away", systemImage: "location.fill")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 18) {
                    Label("RECOMMENDED TRIP", systemImage: "calendar.badge.clock")
                        .font(.caption.bold()).foregroundStyle(.oceanBlue)
                    HStack {
                        tripTime("Launch", launch.launchTime, "arrow.down.circle.fill")
                        Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Spacer()
                        tripTime("Retrieve", launch.retrievalTime, "arrow.up.circle.fill")
                    }
                    Divider()
                    Label("High tide at \(launch.highTide)", systemImage: "water.waves.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                    Text(launch.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Conditions").font(.title3.bold()).foregroundStyle(.deepNavy)
                    HStack(spacing: 12) {
                        conditionTile("wind", "\(launch.windSpeed)", "km/h wind")
                        conditionTile("wind.circle", "\(launch.gustSpeed)", "km/h gusts")
                        conditionTile("water.waves", launch.waveHeight.map { String(format: "%.1f", $0) } ?? "N/A", "m waves")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Why this window?", systemImage: "checkmark.shield.fill")
                        .font(.headline).foregroundStyle(.seaGreen)
                    Text(launch.summary)
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let updated = launch.forecastUpdatedAt {
                        Text("Forecast checked \(updated.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(Color.seaGreen.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(18)
        }
        .background(Color.mist.ignoresSafeArea())
        .navigationTitle("Trip outlook")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tripTime(_ label: String, _ time: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(time).font(.title2.bold()).foregroundStyle(.deepNavy)
        }
    }

    private func conditionTile(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.oceanBlue)
            Text(value).font(.title3.bold()).foregroundStyle(.deepNavy)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
