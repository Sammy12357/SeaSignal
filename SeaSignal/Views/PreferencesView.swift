import SwiftUI

struct PreferencesView: View {
    @AppStorage("maxWindSpeed") private var maxWindSpeed = 24.0
    @AppStorage("maxGustSpeed") private var maxGustSpeed = 32.0
    @AppStorage("maxWaveHeight") private var maxWaveHeight = 0.8
    @AppStorage("highTideWindow") private var highTideWindow = 90.0
    @AppStorage("requireHighTide") private var requireHighTide = false
    @AppStorage("tripLength") private var tripLength = 6.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preferenceSlider(
                        title: "Maximum wind", value: $maxWindSpeed,
                        range: 5...60, step: 1, valueText: "\(Int(maxWindSpeed)) km/h",
                        icon: "wind"
                    )
                    preferenceSlider(
                        title: "Maximum gust", value: $maxGustSpeed,
                        range: 10...80, step: 1, valueText: "\(Int(maxGustSpeed)) km/h",
                        icon: "wind.circle"
                    )
                    preferenceSlider(
                        title: "Maximum wave height", value: $maxWaveHeight,
                        range: 0.1...3, step: 0.1, valueText: String(format: "%.1f m", maxWaveHeight),
                        icon: "water.waves"
                    )
                } header: {
                    Text("Safety limits")
                } footer: {
                    Text("Sea Signal will only recommend trips when the full boating window stays within these limits.")
                }

                Section("Tide preferences") {
                    Toggle(isOn: $requireHighTide) {
                        Label("Require high tide", systemImage: "water.waves.and.arrow.up")
                    }
                    preferenceSlider(
                        title: "High-tide window", value: $highTideWindow,
                        range: 30...180, step: 15, valueText: "±\(Int(highTideWindow)) min",
                        icon: "clock.arrow.circlepath"
                    )
                }

                Section {
                    preferenceSlider(
                        title: "Typical trip length", value: $tripLength,
                        range: 2...12, step: 0.5, valueText: String(format: "%.1f hours", tripLength),
                        icon: "timer"
                    )
                } header: {
                    Text("Trip planning")
                } footer: {
                    Text("We use this duration to find launch and retrieval times that fit your day.")
                }

                Section("Safety") {
                    Label("Forecasts are guidance, not a substitute for local notices, operator judgment, or required safety equipment.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Preferences")
        }
    }

    private func preferenceSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text(valueText).fontWeight(.semibold).foregroundStyle(.oceanBlue)
            }
            Slider(value: value, in: range, step: step)
        }
        .padding(.vertical, 4)
    }
}

