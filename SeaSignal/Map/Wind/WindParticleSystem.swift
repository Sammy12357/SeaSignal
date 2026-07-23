import Foundation

enum WindParticleSystem {
    static func makeParticles(count: Int) -> [WindParticle] {
        var generator = SeededGenerator(seed: 0x5EA51A)
        return (0..<count).map { index in
            WindParticle(
                id: index,
                x: Double.random(in: 0...1, using: &generator),
                y: Double.random(in: 0...1, using: &generator),
                phase: Double.random(in: 0...1, using: &generator),
                length: Double.random(in: 0.55...1.25, using: &generator)
            )
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
