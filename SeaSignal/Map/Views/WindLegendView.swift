import SwiftUI

struct WindLegendView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("WIND")
                    .font(.caption2.weight(.bold))
                Text("knots")
                    .font(.caption2)
                Spacer()
                Text("Surface wind · 10 m")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Color.deepNavy.opacity(0.88))

            ZStack(alignment: .bottom) {
                LinearGradient(gradient: WindPalette.gradient, startPoint: .leading, endPoint: .trailing)
                    .frame(height: 38)
                HStack {
                    ForEach([0, 4, 8, 14, 20, 27, 35, 45, 55], id: \.self) { value in
                        Text("\(value)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 1)
                        if value != 55 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wind speed legend, zero to fifty-five knots")
    }
}
