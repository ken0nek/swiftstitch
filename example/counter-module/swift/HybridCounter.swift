// Spec source + impl for the `Counter` HybridObject.
//
// `nitrogen-swift-input` parses this file and emits `Counter.nitro.ts` + IR.
// Wrapped in `#if canImport(NitroModules)` so the file parses standalone (the
// codegen step is SwiftSyntax-only — never typechecks). The `: HybridCounterSpec`
// inheritance and `NitroModules` import only resolve once `bun nitrogen` has
// produced `nitrogen/generated/ios/swift/HybridCounterSpec.swift` and the Pod
// has installed.

#if canImport(NitroModules)
import NitroModules

public final class HybridCounter: HybridCounterSpec {
    private var current: Int64 = 0

    public override init() { super.init() }

    public func increment() throws { current &+= 1 }

    public func reset() throws { current = 0 }

    public func value() throws -> Int64 { current }

    public func add(delta: Int64) throws -> Int64 {
        current &+= delta
        return current
    }
}
#endif
