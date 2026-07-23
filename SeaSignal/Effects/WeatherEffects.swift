import SwiftUI
import CoreLocation

struct WindArrowView: View {
    let sample: WindSample
    let animated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch sample.speedKPH {
        case ..<12: .cyan
        case ..<25: .seaGreen
        case ..<40: .warningOrange
        default: .dangerRed
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated || reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.4) / 1.4
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

                Image(systemName: "arrow.up")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(color)
                    .offset(y: animated && !reduceMotion ? -3 * sin(phase * .pi) : 0)
                    .rotationEffect(.degrees(sample.directionFromDegrees + 180))
            }
            .scaleEffect(0.92 + min(sample.speedKPH / 160, 0.18))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wind \(Int(sample.speedKPH.rounded())) kilometers per hour")
            .accessibilityValue("From \(Int(sample.directionFromDegrees.rounded())) degrees")
        }
    }
}

struct WindParticleCanvas: View {
    let field: WindField
    let project: (CLLocationCoordinate2D) -> CGPoint?
    let isEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let bounds = (
        minLatitude: 43.22,
        maxLatitude: 44.04,
        minLongitude: -80.02,
        maxLongitude: -78.78
    )

    var body: some View {
        TimelineView(schedule) { timeline in
            Canvas(rendersAsynchronously: true) { context, _ in
                guard isEnabled else { return }
                drawParticles(in: &context, at: timeline.date)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var schedule: AnimationTimelineSchedule {
        .animation(minimumInterval: ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 / 30 : 1 / 60, paused: !isEnabled)
    }

    private func drawParticles(in context: inout GraphicsContext, at date: Date) {
        let particleCount = ProcessInfo.processInfo.isLowPowerModeEnabled ? 140 : 320
        let now = date.timeIntervalSinceReferenceDate
        let activeAnimation = !reduceMotion && scenePhase == .active

        for index in 0..<particleCount {
            let lifetime = 5.5 + seeded(index, salt: 1) * 4
            let phase = activeAnimation
                ? (now + seeded(index, salt: 2) * lifetime).truncatingRemainder(dividingBy: lifetime)
                : seeded(index, salt: 3) * lifetime
            let start = CLLocationCoordinate2D(
                latitude: bounds.minLatitude + seeded(index, salt: 4) * (bounds.maxLatitude - bounds.minLatitude),
                longitude: bounds.minLongitude + seeded(index, salt: 5) * (bounds.maxLongitude - bounds.minLongitude)
            )
            let vector = field.vector(near: start)
            let current = start.advanced(by: vector, seconds: phase)
            let previous = start.advanced(by: vector, seconds: max(phase - 0.14, 0))
            guard let point = project(current), let previousPoint = project(previous) else { continue }

            var trail = Path()
            trail.move(to: previousPoint)
            trail.addLine(to: point)
            let ageOpacity = max(0.12, sin((phase / lifetime) * .pi))
            let speedOpacity = min(0.9, 0.3 + vector.speedMetersPerSecond / 18)
            context.stroke(
                trail,
                with: .color(.cyan.opacity(ageOpacity * speedOpacity)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 1.2, y: point.y - 1.2, width: 2.4, height: 2.4)),
                with: .color(.white.opacity(ageOpacity * 0.85))
            )
        }
    }

    private func seeded(_ index: Int, salt: Int) -> Double {
        var value = UInt64(index &* 1_103_515_245 &+ salt &* 12_345)
        value ^= value >> 16
        value &*= 0x45d9f3b
        value ^= value >> 16
        return Double(value % 10_000) / 10_000
    }
}
