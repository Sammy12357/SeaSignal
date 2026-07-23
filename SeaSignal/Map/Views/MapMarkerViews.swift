import SwiftUI

struct SpotPinView: View {
    let spot: MapSpot
    let isFavorite: Bool

    var body: some View {
        ZStack {
            Image(systemName: "mappin")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(isFavorite ? Color.red : Color.oceanBlue)
                .shadow(color: .black.opacity(0.24), radius: 2, y: 2)
            Image(systemName: isFavorite ? "star.fill" : spot.kind.glyph)
                .font(.system(size: isFavorite ? 15 : 12, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: -5)
        }
        .frame(width: 48, height: 52)
        .contentShape(Rectangle())
        .accessibilityLabel("\(spot.name), \(spot.kind.label)\(isFavorite ? ", favorite" : "")")
    }
}

struct ClusterPinView: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "100+" : "\(count)")
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.deepNavy)
            .frame(minWidth: 58, minHeight: 58)
            .background(.cardBackground, in: Circle())
            .overlay(Circle().stroke(Color.deepNavy.opacity(0.12)))
            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
            .accessibilityLabel("\(count) map locations")
    }
}

struct WindObservationPinView: View {
    let observation: WindObservation

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up")
                .font(.caption.weight(.black))
                .rotationEffect(.degrees(observation.directionDegrees + 180))
            Text("\(Int(observation.speedKnots.rounded()))")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            Text("kt")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.deepNavy)
        .padding(.horizontal, 9)
        .frame(height: 36)
        .background(Color.cardBackground.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(Color.oceanBlue, lineWidth: 2))
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
        .accessibilityLabel(
            "\(observation.stationName), measured wind \(observation.speedKnots.formatted(.number.precision(.fractionLength(0)))) knots from \(observation.compassDirection)"
        )
    }
}

struct WindObservationDetailSheet: View {
    let observation: WindObservation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(observation.stationName)
                            .font(.title3.weight(.bold))
                        Text("NOAA station \(observation.stationID)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Measured wind") {
                    LabeledContent("Speed") {
                        Text("\(formatted(observation.speedKnots)) kt").fontWeight(.semibold)
                    }
                    LabeledContent("Direction") {
                        Text("\(observation.compassDirection) · \(Int(observation.directionDegrees.rounded()))°")
                    }
                    if let gust = observation.gustKnots {
                        LabeledContent("Gust") {
                            Text("\(formatted(gust)) kt")
                        }
                    }
                    LabeledContent("Observed") {
                        Text(observation.observedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    }
                }

                Section("Source") {
                    Link("NOAA National Data Buoy Center", destination: URL(string: "https://www.ndbc.noaa.gov/station_page.php?station=\(observation.stationID.lowercased())")!)
                    Text("This marker is a measured station observation. The colored map and moving wind animation are modeled data from Open-Meteo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Wind observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

struct AirportObservationPinView: View {
    let observation: AirportObservation

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "airplane")
                .font(.caption.weight(.bold))
            if let direction = observation.windDirectionDegrees {
                Image(systemName: "arrow.up")
                    .font(.caption2.weight(.black))
                    .rotationEffect(.degrees(direction + 180))
            }
            Text(observation.windSpeedKnots.map { "\(Int($0.rounded())) kt" } ?? "METAR")
                .font(.system(.caption, design: .rounded, weight: .bold))
        }
        .foregroundStyle(Color.deepNavy)
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(.white.opacity(0.96), in: Capsule())
        .overlay(Capsule().stroke(observation.isStale ? Color.warningOrange : Color.seaGreen, lineWidth: 2))
        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
        .accessibilityLabel("\(observation.stationName), airport weather observation")
    }
}

struct AirportObservationDetailSheet: View {
    let observation: AirportObservation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(observation.stationName).font(.title3.bold())
                    Text("Airport \(observation.stationID)")
                        .foregroundStyle(.secondary)
                }
                Section("Land-based METAR") {
                    if let speed = observation.windSpeedKnots {
                        LabeledContent("Wind", value: "\(speed.formatted(.number.precision(.fractionLength(0)))) kt")
                    }
                    if let direction = observation.windDirectionDegrees {
                        LabeledContent("Direction", value: "\(Int(direction.rounded()))°")
                    } else {
                        LabeledContent("Direction", value: "Variable or unavailable")
                    }
                    if let gust = observation.gustKnots {
                        LabeledContent("Gust", value: "\(gust.formatted(.number.precision(.fractionLength(0)))) kt")
                    }
                    if let visibility = observation.visibilityMiles {
                        LabeledContent("Visibility", value: "\(visibility.formatted()) mi")
                    }
                    if let temperature = observation.temperatureCelsius {
                        LabeledContent("Temperature", value: "\(temperature.formatted()) °C")
                    }
                    if let dewpoint = observation.dewpointCelsius {
                        LabeledContent("Dew point", value: "\(dewpoint.formatted()) °C")
                    }
                    LabeledContent("Observed") {
                        Text(observation.observedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .foregroundStyle(observation.isStale ? Color.warningOrange : Color.primary)
                    }
                }
                Section("Source and limitations") {
                    Link("NOAA/NWS Aviation Weather Center", destination: URL(string: "https://aviationweather.gov/data/api/")!)
                    Text("This is a land-based airport observation. It does not replace a marine observation over open water.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let raw = observation.rawReport {
                        Text(raw).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Airport weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
