import SwiftUI

struct LaunchDetailView: View {
    @EnvironmentObject private var store: LaunchStore
    let launch: BoatLaunch
    @State private var showsTideStations = false

    private var displayedLaunch: BoatLaunch {
        store.launches.first(where: { $0.id == launch.id }) ?? launch
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ConditionBadge(conditions: displayedLaunch.conditions)
                        Spacer()
                        Button { store.toggleFavorite(displayedLaunch) } label: {
                            Image(systemName: store.isFavorite(displayedLaunch) ? "heart.fill" : "heart")
                        }
                    }
                    Text(displayedLaunch.name).font(.largeTitle.bold()).foregroundStyle(.deepNavy)
                    Label("\(displayedLaunch.location) · \(displayedLaunch.distance) away", systemImage: "location.fill")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 18) {
                    Label("RECOMMENDED TRIP", systemImage: "calendar.badge.clock")
                        .font(.caption.bold()).foregroundStyle(.oceanBlue)
                    HStack {
                        tripTime("Launch", displayedLaunch.launchTime, "arrow.down.circle.fill")
                        Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Spacer()
                        tripTime("Retrieve", displayedLaunch.retrievalTime, "arrow.up.circle.fill")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label("High tide: \(displayedLaunch.highTide)", systemImage: "water.waves.and.arrow.up")
                        Label("Low tide: \(displayedLaunch.lowTide)", systemImage: "water.waves.and.arrow.down")
                        Text(displayedLaunch.tideSource)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Choose tide station") { showsTideStations = true }
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    Text(displayedLaunch.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Conditions").font(.title3.bold()).foregroundStyle(.deepNavy)
                    HStack(spacing: 12) {
                        conditionTile("wind", "\(displayedLaunch.windSpeed)", "km/h wind")
                        conditionTile("wind.circle", "\(displayedLaunch.gustSpeed)", "km/h gusts")
                        conditionTile("water.waves", displayedLaunch.waveHeight.map { String(format: "%.1f", $0) } ?? "N/A", "m waves")
                    }
                    HStack(spacing: 12) {
                        conditionTile("cloud.rain", displayedLaunch.rainChance.map(String.init) ?? "N/A", "% rain")
                        conditionTile("timer", displayedLaunch.wavePeriod.map { String(format: "%.0f", $0) } ?? "N/A", "sec period")
                        conditionTile("gauge.with.dots.needle.50percent", displayedLaunch.recommendationScore.map { "\(Int(($0 * 100).rounded()))" } ?? "N/A", "score")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Why this window?", systemImage: "checkmark.shield.fill")
                        .font(.headline).foregroundStyle(.seaGreen)
                    ForEach(displayedLaunch.rationale ?? [displayedLaunch.summary], id: \.self) { reason in
                        Label(reason, systemImage: "checkmark.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let updated = displayedLaunch.forecastUpdatedAt {
                        Text("\(displayedLaunch.forecastIsStale == true ? "Offline forecast from" : "Forecast checked") \(updated.formatted(date: .abbreviated, time: .shortened))")
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
        .sheet(isPresented: $showsTideStations) {
            TideStationPickerView(launch: displayedLaunch).environmentObject(store)
        }
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
