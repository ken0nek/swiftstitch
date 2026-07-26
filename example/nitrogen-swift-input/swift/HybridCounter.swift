// `nitrogen-swift-input` parses this file and emits `Counter.nitro.ts` + IR.
//
// The class is wrapped in `#if canImport(NitroModules)` so the file is happy
// to parse before the pipeline has ever run — `NitroModules` and the
// generated `HybridCounterSpec` only exist after `bun nitrogen` produces the
// bridge under `nitrogen/generated/`. SwiftSyntax walks the inactive branch
// either way, so the parser sees the class regardless.
//
// In a real RN module, the same file would live in your iOS source set
// (e.g. wired into the Pod's source files), so once the pipeline has run the
// `#if` flips on and the impl ships as-is.

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
