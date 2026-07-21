import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: LaunchStore

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
                    } else if let best = store.favorites.first {
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
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyFavorites: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text("No favorite launches").font(.headline)
            Text(store.errorMessage ?? "Choose the ramps you use from the Launches tab.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(30)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SEA SIGNAL")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(.oceanBlue)
                Text("Good morning")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.deepNavy)
                Text("Here’s your outlook for Tuesday")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "bell.fill")
                .foregroundStyle(.oceanBlue)
                .frame(width: 44, height: 44)
                .background(.white, in: Circle())
        }
        .padding(.top, 12)
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

                HStack(spacing: 0) {
                    metric(icon: "wind", value: "\(launch.windSpeed) km/h", label: "Wind")
                    Divider().overlay(.white.opacity(0.4))
                    metric(icon: "water.waves", value: launch.waveHeight.map { String(format: "%.1f m", $0) } ?? "N/A", label: "Waves")
                    Divider().overlay(.white.opacity(0.4))
                    metric(icon: "arrow.up.to.line", value: launch.highTide, label: "High tide")
                }
                .frame(height: 48)

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
        .navigationDestination(for: BoatLaunch.self) { launch in
            LaunchDetailView(launch: launch)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(launch.name).font(.headline).foregroundStyle(.deepNavy)
                    Label("\(launch.location) · \(launch.distance)", systemImage: "location.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ConditionBadge(conditions: launch.conditions)
            }

            Divider()

            if launch.conditions == .avoid || launch.conditions == .loading {
                Text(launch.summary).font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack {
                    timeBlock(title: "LAUNCH", time: launch.launchTime, icon: "arrow.down.circle.fill")
                    Spacer()
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Spacer()
                    timeBlock(title: "RETRIEVE", time: launch.retrievalTime, icon: "arrow.up.circle.fill")
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private func timeBlock(title: String, time: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.oceanBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(time).font(.subheadline.weight(.semibold)).foregroundStyle(.deepNavy)
            }
        }
    }
}
