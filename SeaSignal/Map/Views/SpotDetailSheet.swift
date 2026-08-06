import SwiftUI

struct SpotDetailSheet: View {
    let spot: MapSpot
    @EnvironmentObject private var store: LaunchStore
    @Environment(\.dismiss) private var dismiss

    private var favorite: BoatLaunch? { store.favoriteLaunch(matching: spot) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: spot.kind.glyph)
                            .font(.title2)
                            .foregroundStyle(.oceanBlue)
                            .frame(width: 48, height: 48)
                            .background(Color.oceanBlue.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(spot.name).font(.title2.bold())
                            Text(spot.facilityType?.label ?? spot.kind.label).foregroundStyle(.secondary)
                        }
                    }

                    verificationSummary

                    if let details = spot.details, !details.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(details.keys.sorted(), id: \.self) { key in
                                LabeledContent(key, value: details[key] ?? "")
                                    .font(.subheadline)
                            }
                        }
                        .padding(14)
                        .background(Color.mist, in: RoundedRectangle(cornerRadius: 14))
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

                    correctionActions
                }
                .padding(20)
            }
            .navigationTitle("Map location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var verificationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let level = spot.verificationLevel {
                Label(level.label, systemImage: level == .official ? "checkmark.seal.fill" : "checkmark.seal")
                    .foregroundStyle(level == .official ? Color.seaGreen : .secondary)
            }
            if let access = spot.accessType { Label(access.label, systemImage: "person.badge.key") }
            if let status = spot.operationalStatus {
                Label(status.label, systemImage: status == .open ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(status == .open ? Color.seaGreen : Color.warningOrange)
            }
            if let coordinateType = spot.coordinateType {
                Label(coordinateType.label, systemImage: "scope")
            }
            if let updated = spot.lastVerifiedAt {
                Label("Source updated \(updated.formatted(.dateTime.year().month().day()))", systemImage: "calendar")
            }
            if let provider = spot.provider {
                if let sourceURL = spot.sourceURL.flatMap(URL.init(string:)) {
                    Link(destination: sourceURL) {
                        Label("Source: \(provider)", systemImage: "arrow.up.right.square")
                    }
                } else {
                    Label("Source: \(provider)", systemImage: "info.circle")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var correctionActions: some View {
        Divider()
        ShareLink(item: correctionSummary) {
            Label("Report or share a problem", systemImage: "exclamationmark.bubble")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        if spot.provider == "Florida FWC", let url = fwcReportURL {
            Link(destination: url) {
                Label("Email a status correction to Florida FWC", systemImage: "envelope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var correctionSummary: String {
        """
        SeaSignal boat-ramp correction
        Name: \(spot.name)
        Source ID: \(spot.sourceID ?? "Unavailable")
        Coordinate: \(String(format: "%.6f, %.6f", spot.latitude, spot.longitude))
        Source: \(spot.provider ?? "Unverified")

        Problem and supporting source:
        """
    }

    private var fwcReportURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "BoatRamps@MyFWC.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Boat ramp correction: \(spot.name)"),
            URLQueryItem(name: "body", value: correctionSummary)
        ]
        return components.url
    }
}
