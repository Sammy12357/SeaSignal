import CoreGraphics

struct WindParticle: Identifiable, Hashable {
    let id: Int
    let x: Double
    let y: Double
    let phase: Double
    let length: Double
}
