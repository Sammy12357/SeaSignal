import MapKit
import SwiftUI

struct WindOverlay: View {
    let field: WindField
    let proxy: MapProxy
    let isPaused: Bool
    let lowPowerMode: Bool

    private let normalParticles = WindParticleSystem.makeParticles(count: 320)

    var body: some View {
        TimelineView(.animation(minimumInterval: lowPowerMode ? 1.0 / 18.0 : 1.0 / 30.0, paused: isPaused)) { timeline in
            Canvas { context, _ in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let count = lowPowerMode ? 120 : normalParticles.count
                for particle in normalParticles.prefix(count) {
                    draw(particle, at: time, in: &context)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ particle: WindParticle, at time: TimeInterval, in context: inout GraphicsContext) {
        let baseCoordinate = coordinate(x: particle.x, y: particle.y)
        guard let sample = field.sample(at: baseCoordinate) else { return }
        let speedFactor = max(0.12, min(sample.speed / 22, 1.7))
        let cycle = (time * (0.035 + speedFactor * 0.025) + particle.phase).truncatingRemainder(dividingBy: 1)
        let longitudeScale = sample.u / max(1, field.maxLongitude - field.minLongitude) * 0.0018
        let latitudeScale = sample.v / max(1, field.maxLatitude - field.minLatitude) * 0.0018
        let x = wrapped(particle.x + longitudeScale * cycle)
        let y = wrapped(particle.y + latitudeScale * cycle)
        let headCoordinate = coordinate(x: x, y: y)
        guard let head = proxy.convert(headCoordinate, to: .local) else { return }
        let magnitude = max(sample.speed, 0.1)
        let streakLength = (7 + min(sample.speed, 25) * 0.32) * particle.length
        let tail = CGPoint(
            x: head.x - sample.u / magnitude * streakLength,
            y: head.y + sample.v / magnitude * streakLength
        )
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        context.stroke(path, with: .color(.white.opacity(0.78)), lineWidth: lowPowerMode ? 0.75 : 1.05)
    }

    private func coordinate(x: Double, y: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: field.minLatitude + wrapped(y) * (field.maxLatitude - field.minLatitude),
            longitude: field.minLongitude + wrapped(x) * (field.maxLongitude - field.minLongitude)
        )
    }

    private func wrapped(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 1)
        return result < 0 ? result + 1 : result
    }
}
