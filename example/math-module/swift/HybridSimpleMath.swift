#if canImport(NitroModules)
import NitroModules
#endif

/// Spec source + Android implementation in one file — the SwiftStitch
/// authoring model. `nitrogen-swift-input` reads this to produce the spec, and
/// this same file is what compiles to Embedded Swift for Android.
///
/// Deliberately a bare class, *not* a `HybridSimpleMathSpec` subclass: under
/// Embedded Swift `canImport(NitroModules)` is false, so a class declared
/// inside that guard would vanish and the generated bridge would have nothing
/// to construct. That is also why this file does not yet compile for iOS — see
/// the root README's "Parity bar" section.
public final class HybridSimpleMath {
    public init() {}
    public func add(a: Double, b: Double) -> Double { a + b }
    public func multiply(a: Double, b: Double) -> Double { a * b }
}
