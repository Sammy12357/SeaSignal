import SwiftUI

enum SpotDetailTab: String, CaseIterable, Identifiable {
    case forecast = "Forecast"
    case superforecast = "Superforecast"
    case webcams = "Webcams"
    case spotInfo = "Spot Info"
    var id: Self { self }
}

struct ForecastTableView: View {
    let launch: BoatLaunch

    private var sampledHours: [HourlyConditions] {
        Array((launch.forecastHours ?? []).enumerated().filter { $0.offset % 3 == 0 }.map(\.element).prefix(24))
    }

    private var days: [ForecastDay] {
        let zone = TimeZone(identifier: launch.forecastTimezoneIdentifier ?? "") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return Dictionary(grouping: sampledHours) { calendar.startOfDay(for: $0.time) }
            .map { ForecastDay(date: $0.key, hours: $0.value) }.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            freshness
            if sampledHours.isEmpty {
                ContentUnavailableView("Forecast unavailable", systemImage: "cloud.slash", description: Text("Pull to refresh when you have a connection."))
                    .frame(minHeight: 330)
            } else {
                ScrollView(.horizontal) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(days) { day in
                            Section {
                                ForEach(Array(day.hours.enumerated()), id: \.element.time) { index, hour in
                                    ForecastRow(hour: hour, tide: nextTide(after: hour.time))
                                        .background(index.isMultiple(of: 2) ? Color.cardBackground : Color.mist.opacity(0.55))
                                }
                            } header: {
                                VStack(spacing: 0) {
                                    Text(day.date.formatted(.dateTime.weekday(.wide).month(.twoDigits).day(.twoDigits)).uppercased())
                                        .font(.caption.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                        .background(Color.oceanBlue.opacity(0.12))
                                    ForecastColumnHeader()
                                }
                            }
                        }
                    }
                    .frame(width: 720)
                }
            }
        }
    }

    private var freshness: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Updated: \((launch.forecastUpdatedAt ?? .now).formatted(date: .omitted, time: .shortened))")
                Text("Next: \((launch.forecastUpdatedAt ?? .now).addingTimeInterval(3 * 3600).formatted(date: .omitted, time: .shortened))")
            }.font(.caption).foregroundStyle(.secondary)
            Spacer()
            NavigationLink { ForecastHelpView() } label: { Label("Info", systemImage: "info.circle") }.font(.subheadline.weight(.semibold))
        }.padding(12)
    }

    private func nextTide(after time: Date) -> TideEvent? { launch.tideEvents?.first { $0.time >= time } }
}

private struct ForecastDay: Identifiable {
    let date: Date
    let hours: [HourlyConditions]
    var id: Date { date }
}

private struct ForecastColumnHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Time").frame(width: 72); Text("Wind").frame(width: 140); Text("Weather").frame(width: 92)
            Text("Air").frame(width: 105); Text("Waves").frame(width: 130); Text("Tides").frame(width: 165)
        }.font(.caption2.bold()).foregroundStyle(.secondary).padding(.vertical, 8).background(Color.cardBackground)
    }
}

struct WindStrengthBar: View {
    let speedKPH: Double
    var color: Color { speedKPH < 16 ? .cyan : speedKPH < 28 ? .seaGreen : .orange }
    var body: some View { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 5) }
}

private struct ForecastRow: View {
    let hour: HourlyConditions
    let tide: TideEvent?
    private var knots: Int { Int(((hour.windSpeedKPH ?? 0) * 0.539957).rounded()) }
    private var gusts: Int { Int(((hour.windGustKPH ?? 0) * 0.539957).rounded()) }
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) { WindStrengthBar(speedKPH: hour.windSpeedKPH ?? 0); Text(hour.time.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)))) }
                .frame(width: 72)
            metricArrow(degrees: hour.windDirectionDegrees, primary: "\(knots) kts", secondary: "max \(gusts) kts").frame(width: 140)
            VStack(spacing: 4) { Image(systemName: weatherSymbol).font(.title2); if let rain = hour.precipitationMM, rain > 0 { Text(String(format: "%.2f in", rain / 25.4)) } }.frame(width: 92)
            VStack(spacing: 4) { Text(temperature).font(.headline).padding(5).background(temperatureColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 7)); Text(pressure) }.frame(width: 105)
            metricArrow(degrees: hour.waveDirectionDegrees, primary: hour.waveHeightM.map { String(format: "%.1f ft", $0 * 3.28084) } ?? "—", secondary: hour.wavePeriodSeconds.map { "\(Int($0.rounded())) s" } ?? "—").frame(width: 130)
            tideMetric.frame(width: 165)
        }.font(.caption).frame(minHeight: 64)
    }
    private func metricArrow(degrees: Double?, primary: String, secondary: String) -> some View { HStack { Image(systemName: "arrow.up").rotationEffect(.degrees(degrees ?? 0)); VStack(alignment: .leading) { Text(primary).fontWeight(.bold); Text(secondary).foregroundStyle(.secondary) } } }
    private var tideMetric: some View { HStack { Image(systemName: tide?.kind == .high ? "arrow.up.circle.fill" : "arrow.down.circle.fill").foregroundStyle(tide?.kind == .high ? .cyan : .secondary); VStack(alignment: .leading) { Text(tide?.time.formatted(date: .omitted, time: .shortened) ?? "—").fontWeight(.bold); Text(tide.map { String(format: "%.1f ft", $0.heightM * 3.28084) } ?? "No event").foregroundStyle(.secondary) } } }
    private var temperature: String { hour.airTemperatureC.map { "\(Int(($0 * 9 / 5 + 32).rounded()))°" } ?? "—" }
    private var temperatureColor: Color { (hour.airTemperatureC ?? 15) < 12 ? .blue : (hour.airTemperatureC ?? 15) > 27 ? .orange : .seaGreen }
    private var pressure: String { hour.surfacePressureHPa.map { String(format: "%.2f inHg", $0 * 0.02953) } ?? "—" }
    private var weatherSymbol: String { switch hour.weatherCode ?? 0 { case 51...82: "cloud.rain.fill"; case 1...3: "cloud.sun.fill"; case 45...48: "cloud.fog.fill"; default: hour.isDaylight == false ? "moon.stars.fill" : "sun.max.fill" } }
}

struct ForecastHelpView: View {
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            help("What is the Forecast?", "SeaSignal combines Open-Meteo weather and marine guidance with NOAA tide predictions where a station is available. Forecasts refresh about every three hours and extend up to seven days.")
            help("What is the Superforecast?", "A higher-resolution forecast tier is being evaluated. SeaSignal will only enable it when a reliable source and clear accuracy benefit are available.")
            help("How are tides calculated?", "Tide heights are predictions relative to the reporting station’s local datum. Modeled water levels may be shown where NOAA predictions are unavailable and must not be used for navigation.")
        }.padding(20) }.navigationTitle("Forecast Help").navigationBarTitleDisplayMode(.inline)
    }
    private func help(_ title: String, _ body: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.title3.bold()); Text(body).foregroundStyle(.secondary) } }
}
