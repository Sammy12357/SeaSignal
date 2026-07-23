import SwiftUI

struct ForecastTimelineBar: View {
    @Binding var offsetHours: Int
    let validAt: Date?

    private var displayedDate: Date {
        validAt ?? Calendar.current.date(byAdding: .hour, value: offsetHours, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.subheadline.weight(.semibold))
                    Text(displayedDate.formatted(.dateTime.hour().minute()))
                        .font(.title3.weight(.bold))
                }
                Spacer()
                stepButton(hours: -3, icon: "chevron.left", title: "−3h")
                stepButton(hours: 3, icon: "chevron.right", title: "+3h", iconAfter: true)
            }

            Slider(
                value: Binding(get: { Double(offsetHours) }, set: { offsetHours = Int($0 / 3) * 3 }),
                in: -6...72,
                step: 3
            )
            .tint(.oceanBlue)
            .accessibilityLabel("Forecast time")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func stepButton(hours: Int, icon: String, title: String, iconAfter: Bool = false) -> some View {
        Button {
            offsetHours = min(72, max(-6, offsetHours + hours))
        } label: {
            HStack(spacing: 5) {
                if !iconAfter { Image(systemName: icon) }
                Text(title)
                if iconAfter { Image(systemName: icon) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.deepNavy)
            .frame(height: 42)
            .padding(.horizontal, 8)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
