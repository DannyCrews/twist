/// A small, seedable, `Sendable` random source.
///
/// The game needs randomness it can carry inside a value type and, for tests, reproduce
/// exactly. `SystemRandomNumberGenerator` gives neither, and `any RandomNumberGenerator` is not
/// `Sendable`. This is splitmix64 — three lines, well-distributed, and identical for a given
/// seed on every run.
public struct TwistRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    /// Seeded from the system source, so ordinary play is unpredictable.
    public init() {
        var system = SystemRandomNumberGenerator()
        state = system.next()
    }

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
