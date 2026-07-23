import MapKit
import SwiftUI

enum WindDisplayMode: String, CaseIterable, Identifiable {
    case particleAnimation
    case movingArrows
    case colorOnly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .particleAnimation: "Particle animation"
        case .movingArrows: "Moving arrows"
        case .colorOnly: "Color only"
        }
    }
    var detail: String {
        switch self {
        case .particleAnimation: "Dense moving streaks show wind direction and speed."
        case .movingArrows: "Larger animated arrows make direction easier to read."
        case .colorOnly: "Shows wind speed colors without animation."
        }
    }
}

struct WindOverlay: View {
    let field: WindField
    let region: MKCoordinateRegion
    let mode: WindDisplayMode
    let isPaused: Bool
    let lowPowerMode: Bool

    private let normalParticles = WindParticleSystem.makeParticles(count: 380)

    var body: some View {
        TimelineView(.animation(minimumInterval: lowPowerMode ? 1.0 / 15.0 : 1.0 / 24.0, paused: isPaused)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let normalCount = mode == .movingArrows ? 140 : normalParticles.count
                let count = lowPowerMode ? min(normalCount, mode == .movingArrows ? 60 : 140) : normalCount
                for particle in normalParticles.prefix(count) {
                    draw(particle, at: time, size: size, in: &context)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ particle: WindParticle, at time: TimeInterval, size: CGSize, in context: inout GraphicsContext) {
        let origin = CGPoint(x: CGFloat(particle.x) * size.width, y: CGFloat(particle.y) * size.height)
        let baseCoordinate = coordinate(at: origin, size: size)
        guard let sample = field.sampleClamped(to: baseCoordinate) else { return }
        let magnitude = CGFloat(max(sample.speed, 0.1))
        let direction = CGVector(dx: CGFloat(sample.u) / magnitude, dy: -CGFloat(sample.v) / magnitude)
        let cycleDistance = max(size.width, size.height) * 0.28
        let travelValue = (time * (12 + min(sample.speed, 35) * 1.15) + particle.phase * Double(cycleDistance))
            .truncatingRemainder(dividingBy: Double(cycleDistance))
        let travel = CGFloat(travelValue)
        let head = CGPoint(
            x: wrapped(origin.x + direction.dx * travel, limit: size.width),
            y: wrapped(origin.y + direction.dy * travel, limit: size.height)
        )
        let baseLength = mode == .movingArrows ? 22.0 : 10.0
        let speedLength = mode == .movingArrows ? 0.65 : 0.38
        let streakLength = CGFloat((baseLength + min(sample.speed, 30) * speedLength) * particle.length)
        let tail = CGPoint(
            x: head.x - direction.dx * streakLength,
            y: head.y - direction.dy * streakLength
        )
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        context.stroke(
            path,
            with: .color(.white.opacity(mode == .movingArrows ? 0.90 : 0.76)),
            lineWidth: mode == .movingArrows ? 1.45 : (lowPowerMode ? 0.8 : 1.1)
        )

        if mode == .movingArrows {
            let perpendicular = CGVector(dx: -direction.dy, dy: direction.dx)
            let wingLength = min(7, streakLength * 0.25)
            let wingBase = CGPoint(
                x: head.x - direction.dx * wingLength,
                y: head.y - direction.dy * wingLength
            )
            var arrowhead = Path()
            arrowhead.move(to: CGPoint(x: wingBase.x + perpendicular.dx * wingLength * 0.55, y: wingBase.y + perpendicular.dy * wingLength * 0.55))
            arrowhead.addLine(to: head)
            arrowhead.addLine(to: CGPoint(x: wingBase.x - perpendicular.dx * wingLength * 0.55, y: wingBase.y - perpendicular.dy * wingLength * 0.55))
            context.stroke(arrowhead, with: .color(.white.opacity(0.90)), lineWidth: 1.45)
        }
    }

    private func coordinate(at point: CGPoint, size: CGSize) -> CLLocationCoordinate2D {
        let box = GeoMath.boundingBox(region)
        return CLLocationCoordinate2D(
            latitude: box.north - region.span.latitudeDelta * Double(point.y / max(size.height, 1)),
            longitude: box.west + region.span.longitudeDelta * Double(point.x / max(size.width, 1))
        )
    }

    private func wrapped(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        guard limit > 0 else { return 0 }
        let result = value.truncatingRemainder(dividingBy: limit)
        return result < 0 ? result + limit : result
    }
}
