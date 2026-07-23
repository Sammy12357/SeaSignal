import SwiftUI

struct MapFilterBar: View {
    @Binding var filter: SpotFilter
    @Binding var favoritesOnly: Bool
    @Binding var windLayerMode: WindLayerMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Location type", selection: $filter) {
                        ForEach(SpotFilter.allCases) { value in Text(value.title).tag(value) }
                    }
                } label: {
                    filterLabel(filter.title, systemImage: "line.3.horizontal.decrease.circle.fill")
                }
                filterButton(title: "Favorites", icon: favoritesOnly ? "star.fill" : "star", active: favoritesOnly) {
                    favoritesOnly.toggle()
                }
                Menu {
                    Picker("Wind data", selection: $windLayerMode) {
                        ForEach(WindLayerMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                } label: {
                    filterLabel(windLayerMode.title, systemImage: windLayerMode.systemImage)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.deepNavy)
    }

    private func filterLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(Color.white.opacity(0.94), in: Capsule())
            .overlay(Capsule().stroke(Color.deepNavy.opacity(0.1)))
    }

    private func filterButton(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(active ? Color.oceanBlue.opacity(0.17) : Color.white.opacity(0.94), in: Capsule())
                .overlay(Capsule().stroke(Color.deepNavy.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
