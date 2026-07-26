// Fixture: minimal HybridObject Swift source for the int/number-only scope.
// This is what a user authors. Standard Swift — the `Hybrid` prefix is the
// signal we use to detect HybridObject classes; platform binding is supplied
// via CLI flags, so the user's project compiles before nitrogen runs.

public final class HybridMath {
    public init() {}

    public func add(a: Double, b: Double) throws -> Double {
        return a + b
    }

    public func subtract(a: Int64, b: Int64) -> Int64 {
        return a - b
    }

    public func magnitude(value: Int64) -> UInt64 {
        return UInt64(value < 0 ? -value : value)
    }

    public func reset() {
    }
}
