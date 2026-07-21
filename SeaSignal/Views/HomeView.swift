import SwiftUI

struct HomeView: View {
    private let favorites = BoatLaunch.samples.filter(\.isFavorite)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    bestWindow
                    favoriteSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Color.mist.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
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

    private var bestWindow: some View {
        NavigationLink(value: favorites[0]) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("BEST BOATING WINDOW", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                    Spacer()
                    Image(systemName: "chevron.right")
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Harbourfront Launch")
                        .font(.title2.bold())
                    Text("Today · 7:15 AM–2:30 PM")
                        .font(.headline)
                }

                HStack(spacing: 0) {
                    metric(icon: "wind", value: "9 km/h", label: "Wind")
                    Divider().overlay(.white.opacity(0.4))
                    metric(icon: "water.waves", value: "0.3 m", label: "Waves")
                    Divider().overlay(.white.opacity(0.4))
                    metric(icon: "arrow.up.to.line", value: "7:48 AM", label: "High tide")
                }
                .frame(height: 48)

                Text("Launch near high tide. Conditions remain within your limits until mid-afternoon.")
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
                Text("\(favorites.count) tracked").font(.caption).foregroundStyle(.secondary)
            }

            ForEach(favorites) { launch in
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

            if launch.conditions == .avoid {
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

