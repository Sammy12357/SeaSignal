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
            .background(.white, in: Circle())
            .overlay(Circle().stroke(Color.deepNavy.opacity(0.12)))
            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
            .accessibilityLabel("\(count) map locations")
    }
}
