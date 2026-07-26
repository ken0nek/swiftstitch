# Example: nitrogen-swift-runtime *(stub)*

🚧 **Not yet runnable.** This directory will hold a runnable walkthrough
once `packages/nitrogen-swift-runtime/` lands.

## What this example will demonstrate

The `@HybridObject(ios:android:)` Swift macro path — peer-decl `@c` C-bridge
shims emitted by the compiler at build time, eliminating the codegen-time
`+CBridge.swift` artifact that
[`../nitrogen-swift-embedded/`](../nitrogen-swift-embedded/) writes.

## Pipeline shape

```swift
// swift/HybridCounter.swift
import NitrogenSwift

@HybridObject(ios: .swift, android: .swift)
public final class HybridCounter: HybridCounterSpec {
    public override init() { super.init() }
    public func increment() throws { /* ... */ }
    // The macro emits @c(<C-name>) free-function peer decls per public method.
}
```

The Swift compiler expands the macro to:

```swift
@c("HybridCounter_increment") func _m0(_ handle: OpaquePointer) {
    Unmanaged<HybridCounter>.fromOpaque(handle.toOpaque())
        .takeUnretainedValue()
        .increment()  // …with try!, matching CBridgeEmitter
}
// plus @c create / destroy lifecycle shims; up to 32 method slots per class.
```

| | |
|---|---|
| **Prepare** | A `Hybrid<Name>.swift` class annotated with `@HybridObject(...)`. |
| **Generates** | C-bridge symbols **inline at compile time** — no `+CBridge.swift` file written to disk. |
| **Min toolchain** | Swift 6.3.1 (the macro emits `@c(<C-name>)` peer decls — 6.3-only). |
| **Runtime story** | Lives in [`../rn-app/`](../rn-app/) once that lands. |

## When to pick this over `nitrogen-swift-embedded`

Both produce the same C linker symbol shape (`<ClassName>_<methodName>`).
The macro is an **alternative**, not a layer on top:

- `-runtime`: shims emitted as peer decls of your class, at compile time.
  No file artifact. Requires Swift 6.3.1.
- `-embedded`: shims emitted as a separate `Hybrid<Foo>+CBridge.swift` file
  by the codegen step. Works on the Swift toolchain `-embedded` itself
  needs (also 6.3.1 for the Embedded compile, but the *codegen* step is
  toolchain-agnostic).

The macro path is only useful **end-to-end after** the C++ glue + CMake
recipe land (currently in the `-embedded` package). On its own, the emitted
`@c` symbols have nothing on the C++ side to call them — so this example
will demonstrate the macro mechanics in isolation, with the linkage story
shown via `-embedded`.

## See also

- [`packages/nitrogen-swift-runtime/`](../../packages/) *(not yet present)*
- [`../nitrogen-swift-embedded/`](../nitrogen-swift-embedded/) — alternative C-bridge emitter (codegen-time).
