import SwiftUI

struct ConditionBadge: View {
    let conditions: BoatLaunch.Conditions

    private var color: Color {
        switch conditions {
        case .ideal: .seaGreen
        case .caution: .warningOrange
        case .avoid: .dangerRed
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

extension Color {
    static let oceanBlue = Color(red: 0.05, green: 0.36, blue: 0.57)
    static let deepNavy = Color(red: 0.03, green: 0.15, blue: 0.24)
    static let seaGreen = Color(red: 0.05, green: 0.57, blue: 0.43)
    static let warningOrange = Color(red: 0.91, green: 0.52, blue: 0.12)
    static let dangerRed = Color(red: 0.84, green: 0.22, blue: 0.24)
    static let mist = Color(red: 0.94, green: 0.97, blue: 0.98)
}

