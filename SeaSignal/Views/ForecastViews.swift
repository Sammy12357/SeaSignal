import SwiftUI

enum SpotDetailTab: String, CaseIterable, Identifiable {
    case forecast = "Forecast"
    case superforecast = "Superforecast"
    case webcams = "Webcams"
    case spotInfo = "Spot Info"
    var id: Self { self }
}

enum ForecastUnits {
    static func knots(fromKPH value: Double?) -> Int? {
        value.map { Int(($0 * 0.539957).rounded()) }
    }

    static func fahrenheit(fromCelsius value: Double?) -> Int? {
        value.map { Int(($0 * 9 / 5 + 32).rounded()) }
    }

    static func inchesOfMercury(fromHectopascals value: Double?) -> Double? {
        value.map { $0 * 0.029529983071445 }
    }

    static func feet(fromMetres value: Double?) -> Double? {
        value.map { $0 * 3.280839895 }
    }

    static func inches(fromMillimetres value: Double?) -> Double? {
        value.map { $0 / 25.4 }
    }
}

enum ForecastPresentation {
    static func sampledHours(_ hours: [HourlyConditions]) -> [HourlyConditions] {
        hours.enumerated().compactMap { index, hour in index.isMultiple(of: 3) ? hour : nil }
    }

    static func nextTide(after time: Date, events: [TideEvent]) -> TideEvent? {
        events.filter { $0.time >= time }.min { $0.time < $1.time }
    }

    static func timeZone(identifier: String?) -> TimeZone {
        identifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    static func string(from date: Date, timeZone: TimeZone, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

struct ForecastTableView: View {
    let launch: BoatLaunch

    private var sampledHours: [HourlyConditions] {
        ForecastPresentation.sampledHours(launch.forecastHours ?? [])
    }

    private var timeZone: TimeZone {
        ForecastPresentation.timeZone(identifier: launch.forecastTimezoneIdentifier)
    }

    private var days: [ForecastDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return Dictionary(grouping: sampledHours) { calendar.startOfDay(for: $0.time) }
            .map { ForecastDay(date: $0.key, hours: $0.value.sorted { $0.time < $1.time }) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            freshness

            if sampledHours.isEmpty, launch.conditions == .loading {
                ProgressView("Loading forecast…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading forecast data")
            } else if sampledHours.isEmpty {
                ContentUnavailableView(
                    "Forecast unavailable",
                    systemImage: "cloud.slash",
                    description: Text("Reconnect and refresh to download forecast measurements for this launch.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(days) { day in
                            Section {
                                ForEach(Array(day.hours.enumerated()), id: \.element.time) { index, hour in
                                    ForecastRow(
                                        hour: hour,
                                        tide: ForecastPresentation.nextTide(
                                            after: hour.time,
                                            events: launch.tideEvents ?? []
                                        ),
                                        timeZone: timeZone
                                    )
                                    .background(index.isMultiple(of: 2) ? Color.cardBackground : Color.mist.opacity(0.55))
                                }
                            } header: {
                                VStack(spacing: 0) {
                                    Text(ForecastPresentation.string(from: day.date, timeZone: timeZone, format: "EEEE, MM/dd").uppercased())
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(Color.oceanBlue.opacity(0.12))
                                    ForecastColumnHeader()
                                }
                            }
                        }
                    }
                    .frame(width: 720)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var freshness: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let updated = launch.forecastUpdatedAt {
                    Text("Updated: \(ForecastPresentation.string(from: updated, timeZone: timeZone, format: "MMM d, h:mm a z"))")
                    let nextRefresh = updated.addingTimeInterval(3 * 3600)
                    Text(nextRefresh <= .now
                         ? "Refresh due"
                         : "Next refresh: \(ForecastPresentation.string(from: nextRefresh, timeZone: timeZone, format: "h:mm a z"))")
                } else {
                    Text("Updated: Not yet available")
                    Text("Next refresh: After a successful update")
                }
                if launch.forecastIsStale == true {
                    Label("Offline — saved forecast", systemImage: "wifi.slash")
                        .foregroundStyle(Color.warningOrange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            NavigationLink { ForecastHelpView() } label: {
                Label("Forecast Info", systemImage: "info.circle")
            }
            .font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct ForecastDay: Identifiable {
    let date: Date
    let hours: [HourlyConditions]
    var id: Date { date }
}

private struct ForecastColumnHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Time").frame(width: 72)
            Text("Wind").frame(width: 140)
            Text("Weather").frame(width: 92)
            Text("Air").frame(width: 105)
            Text("Waves").frame(width: 130)
            Text("Tides").frame(width: 181)
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .background(Color.cardBackground)
    }
}

struct WindStrengthBar: View {
    let speedKPH: Double?

    private var color: Color {
        guard let speedKPH else { return .clear }
        return speedKPH < 16 ? .cyan : speedKPH < 28 ? .seaGreen : .orange
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 5)
            .accessibilityHidden(true)
    }
}

private struct ForecastRow: View {
    let hour: HourlyConditions
    let tide: TideEvent?
    let timeZone: TimeZone

    private var knots: Int? { ForecastUnits.knots(fromKPH: hour.windSpeedKPH) }
    private var gusts: Int? { ForecastUnits.knots(fromKPH: hour.windGustKPH) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                WindStrengthBar(speedKPH: hour.windSpeedKPH)
                Text(ForecastPresentation.string(from: hour.time, timeZone: timeZone, format: "hh a"))
            }
            .frame(width: 72)

            metricArrow(
                degrees: hour.windDirectionDegrees,
                primary: knots.map { "\($0) kts" } ?? "—",
                secondary: gusts.map { "max \($0) kts" } ?? "gust unavailable"
            )
            .frame(width: 140)

            VStack(spacing: 4) {
                Image(systemName: weatherSymbol)
                    .font(.title2)
                if let rain = ForecastUnits.inches(fromMillimetres: hour.precipitationMM), rain > 0 {
                    Text(String(format: "%.2f in", rain))
                }
            }
            .frame(width: 92)

            VStack(spacing: 4) {
                Text(temperature)
                    .font(.headline)
                    .padding(5)
                    .background(temperatureColor.opacity(hour.airTemperatureC == nil ? 0 : 0.18), in: RoundedRectangle(cornerRadius: 7))
                Text(pressure)
            }
            .frame(width: 105)

            metricArrow(
                degrees: hour.waveDirectionDegrees,
                primary: ForecastUnits.feet(fromMetres: hour.waveHeightM).map { String(format: "%.1f ft", $0) } ?? "—",
                secondary: hour.wavePeriodSeconds.map { "\(Int($0.rounded())) s" } ?? "period unavailable"
            )
            .frame(width: 130)

            tideMetric.frame(width: 181)
        }
        .font(.caption)
        .frame(minHeight: 68)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func metricArrow(degrees: Double?, primary: String, secondary: String) -> some View {
        HStack {
            if let degrees {
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(degrees))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading) {
                Text(primary).fontWeight(.bold)
                Text(secondary).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var tideMetric: some View {
        if let tide {
            HStack {
                Image(systemName: tide.kind == .high ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(tide.kind == .high ? .cyan : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("\(tide.kind == .high ? "High" : "Low") · \(ForecastPresentation.string(from: tide.time, timeZone: timeZone, format: "h:mm a"))")
                        .fontWeight(.bold)
                    Text(ForecastUnits.feet(fromMetres: tide.heightM).map { String(format: "%.1f ft", $0) } ?? "Height unavailable")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No tide event")
                .foregroundStyle(.secondary)
        }
    }

    private var temperature: String {
        ForecastUnits.fahrenheit(fromCelsius: hour.airTemperatureC).map { "\($0)°F" } ?? "—"
    }

    private var temperatureColor: Color {
        guard let temperature = hour.airTemperatureC else { return .clear }
        return temperature < 12 ? .blue : temperature > 27 ? .orange : .seaGreen
    }

    private var pressure: String {
        ForecastUnits.inchesOfMercury(fromHectopascals: hour.surfacePressureHPa)
            .map { String(format: "%.2f inHg", $0) } ?? "—"
    }

    private var weatherSymbol: String {
        guard let code = hour.weatherCode else { return "questionmark.circle" }
        switch code {
        case 0: return hour.isDaylight == false ? "moon.stars.fill" : "sun.max.fill"
        case 1...3: return "cloud.sun.fill"
        case 45...48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85...86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle"
        }
    }

    private var accessibilitySummary: String {
        var values = [ForecastPresentation.string(from: hour.time, timeZone: timeZone, format: "EEEE h:mm a")]
        values.append(knots.map { "Wind \($0) knots" } ?? "Wind unavailable")
        if let gusts { values.append("Gusts \(gusts) knots") }
        if let temperature = ForecastUnits.fahrenheit(fromCelsius: hour.airTemperatureC) { values.append("Temperature \(temperature) degrees Fahrenheit") }
        if let pressure = ForecastUnits.inchesOfMercury(fromHectopascals: hour.surfacePressureHPa) { values.append(String(format: "Pressure %.2f inches of mercury", pressure)) }
        if let height = ForecastUnits.feet(fromMetres: hour.waveHeightM) { values.append(String(format: "Waves %.1f feet", height)) }
        if let tide { values.append("Next \(tide.kind == .high ? "high" : "low") tide \(ForecastPresentation.string(from: tide.time, timeZone: timeZone, format: "h:mm a"))") }
        return values.joined(separator: ", ")
    }
}

struct ForecastHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                help("What is the Forecast?", "SeaSignal combines Open-Meteo weather and marine guidance with NOAA tide predictions where a station is available. Forecasts refresh about every three hours and extend up to seven days.")
                help("What is the Superforecast?", "A higher-resolution forecast tier is being evaluated. SeaSignal will only enable it when a reliable source and clear accuracy benefit are available.")
                help("How are tides calculated?", "Tide heights are predictions relative to the reporting station’s local datum. Modeled water levels may be shown where NOAA predictions are unavailable and must not be used for navigation.")
            }
            .padding(20)
        }
        .navigationTitle("Forecast Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func help(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.bold())
            Text(body).foregroundStyle(.secondary)
        }
    }
}
