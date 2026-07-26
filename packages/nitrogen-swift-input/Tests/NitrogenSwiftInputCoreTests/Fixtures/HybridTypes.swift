// Comprehensive int/number-only type matrix. Every primitive in scope appears
// as a parameter and as a return type so the emitter and parser are exercised
// across the full surface, not just the methods that happen to live on
// `HybridMath`. Standard Swift — platform binding is supplied via CLI flags.

public final class HybridTypes {
    public init() {}

    public func passBool(value: Bool) -> Bool {
        return value
    }

    public func passDouble(value: Double) -> Double {
        return value
    }

    public func passFloat(value: Float) -> Float {
        return value
    }

    public func passInt64(value: Int64) -> Int64 {
        return value
    }

    public func passUInt64(value: UInt64) -> UInt64 {
        return value
    }

    public func returnsVoid() {
    }

    public func explicitVoid() -> () {
    }

    public func throwingAdd(a: Double, b: Double) throws -> Double {
        return a + b
    }

    public func noArgs() -> Int64 {
        return 0
    }
}
