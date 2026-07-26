// E2E fixture: iOS-only HybridObject. Standard Swift (no fictional
// attributes), so it compiles in the user's project independently of nitrogen.

public final class HybridSimpleMath {
    public init() {}

    public func add(a: Double, b: Double) -> Double {
        return a + b
    }

    public func subtract(a: Int64, b: Int64) -> Int64 {
        return a - b
    }
}
