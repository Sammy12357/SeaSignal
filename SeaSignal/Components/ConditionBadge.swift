import SwiftUI

struct ConditionBadge: View {
    let conditions: BoatLaunch.Conditions

    private var color: Color {
        switch conditions {
        case .ideal: .seaGreen
        case .caution: .warningOrange
        case .avoid: .dangerRed
        case .loading: .oceanBlue
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(conditions.rawValue)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }
}

extension ShapeStyle where Self == Color {
    static var oceanBlue: Color { Color(red: 0.05, green: 0.36, blue: 0.57) }
    static var deepNavy: Color { Color(uiColor: .label) }
    static var seaGreen: Color { Color(red: 0.05, green: 0.57, blue: 0.43) }
    static var warningOrange: Color { Color(red: 0.91, green: 0.52, blue: 0.12) }
    static var dangerRed: Color { Color(red: 0.84, green: 0.22, blue: 0.24) }
    static var mist: Color { Color(uiColor: .systemGroupedBackground) }
    static var cardBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
}
