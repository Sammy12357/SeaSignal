import SwiftUI

struct MapFilterBar: View {
    @Binding var filter: SpotFilter
    @Binding var favoritesOnly: Bool
    @Binding var windLayerMode: WindLayerMode

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Location type", selection: $filter) {
                    ForEach(SpotFilter.allCases) { value in Text(value.title).tag(value) }
                }
            } label: {
                Label(filter.title, systemImage: "line.3.horizontal.decrease.circle.fill")
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.94), in: Capsule())
                    .overlay(Capsule().stroke(Color.deepNavy.opacity(0.1)))
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
                Label(windLayerMode.title, systemImage: windLayerMode.systemImage)
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.94), in: Capsule())
                    .overlay(Capsule().stroke(Color.deepNavy.opacity(0.1)))
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.deepNavy)
    }

    private func filterButton(title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(active ? Color.oceanBlue.opacity(0.17) : Color.white.opacity(0.94), in: Capsule())
                .overlay(Capsule().stroke(Color.deepNavy.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
