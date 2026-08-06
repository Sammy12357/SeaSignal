import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: LaunchStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    if store.authorizationStatus == .notDetermined {
                        locationRequestCard
                    } else if store.isLoading && store.launches.isEmpty {
                        ProgressView("Finding nearby boat ramps…")
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    } else if let best = store.bestFavorite {
                        bestWindow(best)
                        favoriteSection
                    } else {
                        emptyFavorites
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Color.mist.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BoatLaunch.self) { launch in
                LaunchDetailView(launch: launch)
            }
        }
    }

    private var locationRequestCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "location.circle.fill").font(.system(size: 42)).foregroundStyle(.oceanBlue)
            Text("Find launches near you").font(.title3.bold())
            Text("Allow your location to find nearby boat ramps and automatically select the closest three.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Use My Location") { store.start() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.cardBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyFavorites: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text("No favorite launches").font(.headline)
            Text(store.errorMessage ?? "Choose the ramps you use from the Launches tab.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(30)
        .background(.cardBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                greetingText
                Spacer()
                notificationIcon
            }
            VStack(alignment: .leading, spacing: 12) {
                greetingText
                notificationIcon
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private var greetingText: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("SEA SIGNAL")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(.oceanBlue)
                Text(dynamicTypeSize.isAccessibilitySize
                     ? greeting.replacingOccurrences(of: " ", with: "\n")
                     : greeting)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.deepNavy)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Here’s your outlook for \(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notificationIcon: some View {
        Image(systemName: "bell.fill")
            .foregroundStyle(.oceanBlue)
            .frame(width: 44, height: 44)
            .background(.cardBackground, in: Circle())
            .accessibilityLabel("Alerts")
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private func bestWindow(_ launch: BoatLaunch) -> some View {
        NavigationLink(value: launch) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("BEST BOATING WINDOW", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                    Spacer()
                    Image(systemName: "chevron.right")
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(launch.name)
                        .font(.title2.bold())
                    Text("\(launch.launchTime)–\(launch.retrievalTime)")
                        .font(.headline)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        bestWindowMetrics(for: launch)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        bestWindowMetrics(for: launch)
                    }
                }

                Text(launch.summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(
                LinearGradient(colors: [.oceanBlue, Color(red: 0.04, green: 0.53, blue: 0.66)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24)
            )
            .shadow(color: .oceanBlue.opacity(0.22), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func bestWindowMetrics(for launch: BoatLaunch) -> some View {
        let current = currentConditions(for: launch)
        metric(
            icon: "wind",
            value: ForecastUnits.knots(fromKPH: current?.windSpeedKPH).map { "\($0) kts" } ?? "Unavailable",
            label: "Wind"
        )
        Divider().overlay(.white.opacity(0.4))
        metric(
            icon: "water.waves",
            value: ForecastUnits.feet(fromMetres: current?.waveHeightM).map { String(format: "%.1f ft", $0) } ?? "Unavailable",
            label: "Waves"
        )
        Divider().overlay(.white.opacity(0.4))
        metric(icon: "arrow.up.to.line", value: compactTide(launch.highTide), label: "High tide")
    }

    private func currentConditions(for launch: BoatLaunch) -> HourlyConditions? {
        (launch.forecastHours ?? []).min {
            abs($0.time.timeIntervalSinceNow) < abs($1.time.timeIntervalSinceNow)
        }
    }

    private func metric(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(value).fontWeight(.semibold)
            }
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.72))
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
    }

    private func compactTide(_ value: String) -> String {
        if value.contains("Not available") || value == "Unavailable" { return "N/A" }
        let raw = value.components(separatedBy: " · ").last ?? value
        let parts = raw.split(separator: " ")
        return parts.count >= 3 ? parts.suffix(2).joined(separator: " ") : raw
    }

    private var favoriteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Favorite launches").font(.title3.bold()).foregroundStyle(.deepNavy)
                Spacer()
                Text("\(store.favorites.count) tracked").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(store.favorites) { launch in
                NavigationLink(value: launch) {
                    LaunchCard(launch: launch)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LaunchCard: View {
    let launch: BoatLaunch

    private var current: HourlyConditions? {
        (launch.forecastHours ?? []).min { abs($0.time.timeIntervalSinceNow) < abs($1.time.timeIntervalSinceNow) }
    }

    private var weatherSymbol: String {
        guard let code = current?.weatherCode else { return "questionmark.circle" }
        switch code {
        case 0: return current?.isDaylight == false ? "moon.stars.fill" : "sun.max.fill"
        case 1...3: return "cloud.sun.fill"
        case 45...48: return "cloud.fog.fill"
        case 51...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85...86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            WindStrengthBar(speedKPH: current?.windSpeedKPH)
                .frame(height: 64)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(launch.name)
                            .font(.headline)
                            .foregroundStyle(.deepNavy)
                            .lineLimit(2)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(statusColor)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "map.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.oceanBlue)
                        .accessibilityHidden(true)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { measurementItems }
                    VStack(alignment: .leading, spacing: 7) { measurementItems }
                }
            }
        }
        .padding(12)
        .background(.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var measurementItems: some View {
        measurement(
            icon: current?.windDirectionDegrees == nil ? "wind" : "arrow.up",
            rotation: current?.windDirectionDegrees,
            value: ForecastUnits.knots(fromKPH: current?.windSpeedKPH).map { "\($0) kts" } ?? "Wind —"
        )
        measurement(
            icon: "wind.circle",
            value: ForecastUnits.knots(fromKPH: current?.windGustKPH).map { "Gust \($0) kts" } ?? "Gust —"
        )
        measurement(icon: weatherSymbol, value: weatherText)
        measurement(
            icon: "thermometer.medium",
            value: ForecastUnits.fahrenheit(fromCelsius: current?.airTemperatureC).map { "\($0)°F" } ?? "Air —"
        )
    }

    private func measurement(icon: String, rotation: Double? = nil, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .rotationEffect(.degrees(rotation ?? 0))
                .foregroundStyle(.oceanBlue)
            Text(value).font(.caption.weight(.semibold))
        }
    }

    private var weatherText: String {
        guard let code = current?.weatherCode else { return "Weather —" }
        switch code {
        case 0: return "Clear"
        case 1...3: return "Cloudy"
        case 45...48: return "Fog"
        case 51...67, 80...82: return "Rain"
        case 71...77, 85...86: return "Snow"
        case 95...99: return "Storms"
        default: return "Weather code \(code)"
        }
    }

    private var statusText: String {
        if launch.forecastIsStale == true { return "Offline · saved forecast" }
        if launch.conditions == .loading { return "Updating forecast" }
        if launch.forecastHours?.isEmpty != false { return "Forecast unavailable" }
        return "\(launch.conditions.rawValue) forecast · \(launch.location)"
    }

    private var statusColor: Color {
        if launch.forecastIsStale == true { return .warningOrange }
        if launch.conditions == .ideal { return .seaGreen }
        return .secondary
    }

    private var accessibilitySummary: String {
        var values = [launch.name, statusText]
        if let wind = ForecastUnits.knots(fromKPH: current?.windSpeedKPH) { values.append("Wind \(wind) knots") }
        if let gust = ForecastUnits.knots(fromKPH: current?.windGustKPH) { values.append("Gusts \(gust) knots") }
        if let temperature = ForecastUnits.fahrenheit(fromCelsius: current?.airTemperatureC) { values.append("Temperature \(temperature) degrees Fahrenheit") }
        return values.joined(separator: ", ")
    }
}
