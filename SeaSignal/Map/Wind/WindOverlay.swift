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
        case .movingArrows: "Direction arrows"
        case .colorOnly: "Color only"
        }
    }
    var detail: String {
        switch self {
        case .particleAnimation: "Dense moving streaks show wind direction and speed."
        case .movingArrows: "Stationary colored arrows show direction and speed without covering land."
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

    @ViewBuilder
    var body: some View {
        TimelineView(.animation(minimumInterval: lowPowerMode ? 1.0 / 15.0 : 1.0 / 24.0, paused: isPaused)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = lowPowerMode ? min(normalParticles.count, 140) : normalParticles.count
                for particle in normalParticles.prefix(count) {
                    drawParticle(particle, at: time, size: size, in: &context)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawParticle(_ particle: WindParticle, at time: TimeInterval, size: CGSize, in context: inout GraphicsContext) {
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
        guard field.isWater(at: coordinate(at: head, size: size)) else { return }
        let streakLength = CGFloat((10 + min(sample.speed, 30) * 0.38) * particle.length)
        let tail = CGPoint(
            x: head.x - direction.dx * streakLength,
            y: head.y - direction.dy * streakLength
        )
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        context.stroke(
            path,
            with: .color(.white.opacity(0.76)),
            lineWidth: lowPowerMode ? 0.8 : 1.1
        )
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

struct WindDirectionArrowOverlay: View {
    let field: WindField
    let proxy: MapProxy
    let lowPowerMode: Bool

    var body: some View {
        ZStack {
            ForEach(0..<(field.rows * field.columns), id: \.self) { index in
                let row = index / field.columns
                let column = index % field.columns
                let coordinate = field.coordinate(row: row, column: column)

                if (!lowPowerMode || (row.isMultiple(of: 2) && column.isMultiple(of: 2))),
                   field.isWater(at: coordinate),
                   let sample = field.sample(at: coordinate),
                   let point = proxy.convert(coordinate, to: .local) {
                    WindDirectionArrowGlyph(sample: sample)
                        .position(point)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WindDirectionArrowGlyph: View {
    let sample: (u: Double, v: Double, speed: Double)

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let magnitude = CGFloat(max(sample.speed, 0.1))
            let direction = CGVector(dx: CGFloat(sample.u) / magnitude, dy: -CGFloat(sample.v) / magnitude)
            let length = CGFloat(18 + min(sample.speed, 30) * 0.55)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let tail = CGPoint(
                x: center.x - direction.dx * length * 0.5,
                y: center.y - direction.dy * length * 0.5
            )
            let head = CGPoint(
                x: center.x + direction.dx * length * 0.5,
                y: center.y + direction.dy * length * 0.5
            )
            let color = WindPalette.color(for: sample.speed)
            var shaft = Path()
            shaft.move(to: tail)
            shaft.addLine(to: head)
            context.stroke(shaft, with: .color(.black.opacity(0.35)), lineWidth: 3.6)
            context.stroke(shaft, with: .color(color), lineWidth: 2.1)

            let perpendicular = CGVector(dx: -direction.dy, dy: direction.dx)
            let wingLength = min(8, length * 0.28)
            let wingBase = CGPoint(
                x: head.x - direction.dx * wingLength,
                y: head.y - direction.dy * wingLength
            )
            var arrowhead = Path()
            arrowhead.move(to: CGPoint(
                x: wingBase.x + perpendicular.dx * wingLength * 0.55,
                y: wingBase.y + perpendicular.dy * wingLength * 0.55
            ))
            arrowhead.addLine(to: head)
            arrowhead.addLine(to: CGPoint(
                x: wingBase.x - perpendicular.dx * wingLength * 0.55,
                y: wingBase.y - perpendicular.dy * wingLength * 0.55
            ))
            context.stroke(arrowhead, with: .color(.black.opacity(0.35)), lineWidth: 3.6)
            context.stroke(arrowhead, with: .color(color), lineWidth: 2.1)
        }
        .frame(width: 38, height: 38)
    }
}
