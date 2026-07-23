import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var store: LaunchStore
    @AppStorage("maxWindSpeed") private var maxWindSpeed = 24.0
    @AppStorage("maxGustSpeed") private var maxGustSpeed = 32.0
    @AppStorage("maxWaveHeight") private var maxWaveHeight = 0.8
    @AppStorage("highTideWindow") private var highTideWindow = 90.0
    @AppStorage("requireHighTide") private var requireHighTide = false
    @AppStorage("tripLength") private var tripLength = 6.0
    @AppStorage("maxRainProbability") private var maxRainProbability = 50.0
    @AppStorage("requireDaylight") private var requireDaylight = true
    @AppStorage("weeklyNotificationsEnabled") private var weeklyNotificationsEnabled = false
    @AppStorage("notificationWeekday") private var notificationWeekday = 5
    @AppStorage("notificationHour") private var notificationHour = 18
    @State private var notificationDenied = false

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
                    preferenceSlider(
                        title: "Maximum rain chance", value: $maxRainProbability,
                        range: 0...100, step: 5, valueText: "\(Int(maxRainProbability))%",
                        icon: "cloud.rain"
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
                    Toggle(isOn: $requireDaylight) {
                        Label("Daylight trips only", systemImage: "sun.max.fill")
                    }
                } header: {
                    Text("Trip planning")
                } footer: {
                    Text("We use this duration to find launch and retrieval times that fit your day.")
                }

                Section {
                    Toggle(isOn: $weeklyNotificationsEnabled) {
                        Label("Weekly boating outlook", systemImage: "bell.badge")
                    }
                    .onChange(of: weeklyNotificationsEnabled) { _, enabled in
                        Task {
                            if enabled {
                                let allowed = await WeeklyNotificationService.requestAuthorization()
                                if !allowed {
                                    weeklyNotificationsEnabled = false
                                    notificationDenied = true
                                    return
                                }
                            }
                            await WeeklyNotificationService.update(using: store.favorites)
                        }
                    }

                    if weeklyNotificationsEnabled {
                        Picker("Day", selection: $notificationWeekday) {
                            Text("Sunday").tag(1)
                            Text("Monday").tag(2)
                            Text("Tuesday").tag(3)
                            Text("Wednesday").tag(4)
                            Text("Thursday").tag(5)
                            Text("Friday").tag(6)
                            Text("Saturday").tag(7)
                        }
                        Picker("Time", selection: $notificationHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(hourLabel(hour)).tag(hour)
                            }
                        }
                        .onChange(of: notificationWeekday) { _, _ in rescheduleNotification() }
                        .onChange(of: notificationHour) { _, _ in rescheduleNotification() }
                    }
                } header: {
                    Text("Weekly outlook")
                } footer: {
                    Text("Sea Signal refreshes the notification when the app opens and requests best-effort background updates from iOS.")
                }

                Section {
                    Button {
                        Task { await store.refreshForecasts(ids: Set(store.favorites.map(\.id))) }
                    } label: {
                        Label("Recalculate favorite launches", systemImage: "arrow.clockwise")
                    }
                }

                Section("Safety") {
                    Label("Forecasts are guidance, not a substitute for local notices, operator judgment, or required safety equipment.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Preferences")
            .alert("Notifications are off", isPresented: $notificationDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enable notifications for Sea Signal in the iPhone Settings app to receive the weekly outlook.")
            }
        }
    }

    private func rescheduleNotification() {
        Task { await WeeklyNotificationService.update(using: store.favorites) }
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date())
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
