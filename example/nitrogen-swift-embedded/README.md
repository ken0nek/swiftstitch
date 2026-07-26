# Example: nitrogen-swift-embedded *(stub)*

🚧 **Not yet runnable.** This directory will hold a runnable walkthrough
once `packages/nitrogen-swift-embedded/` lands.

## What this example will demonstrate

First-class Swift on Android with **no Swift runtime in the APK**:

- `+CBridge.swift` (the `@c` C-ABI front to user methods)
- `Hybrid<Foo>.hpp` (concrete C++ subclass forwarding to `extern "C"` symbols)
- An Embedded Swift `.o` linked into `libMyApp.so` whose `DT_NEEDED`
  contains only bionic + `libc++_shared` — no Swift stdlib overlay in
  `jniLibs/`, no per-Hybrid `.so`.

## Pipeline shape

```
specs/Counter.ir.json + swift/HybridCounter.swift
   │  nitrogen-swift-embedded emit
   ▼
{Hybrid<Foo>+CBridge.swift,  Hybrid<Foo>.hpp,  CMakeLists.txt fragment}
   │  swiftc -target *-none-none-elf -enable-experimental-feature Embedded
   │         -enable-experimental-feature CImplementation -wmo -parse-as-library -c
   ▼
build/<abi>/Hybrid<Foo>.o
   │  Android NDK linker (driven by the emitted CMake recipe)
   ▼
libMyApp.so   ← contains Embedded Swift code, links bionic + libc++_shared only
```

| | |
|---|---|
| **Prepare** | IR JSON (from `nitrogen-swift-input` or `-bridgejs`) + the directory holding `Hybrid<Name>.swift` impl files. |
| **Generates** | `+CBridge.swift`, `Hybrid<Foo>.hpp`, CMake fragment, and `.o` per ABI. |
| **Min toolchain** | Swift 6.3.1 + Android NDK r27+. |
| **Runtime story** | Lives in [`../rn-app/`](../rn-app/) once that lands. |

The example will gate the NDK link step on toolchain detection — it skips
cleanly if `NITRO_SWIFTC` or the NDK isn't installed.

## Environment

| Env var | Purpose |
|---|---|
| `NITRO_SWIFTC` | Path to a Swift 6.3+ `swiftc` (typically a `.xctoolchain` install or swift-android-sdk). |
| `NITRO_USER_SWIFT_DIR` | Directory containing `Hybrid<Name>.swift` impls — passed at native build time. |

## See also

- [`packages/nitrogen-swift-embedded/`](../../packages/) *(not yet present)*
- [`../nitrogen-swift-runtime/`](../nitrogen-swift-runtime/) — alternative C-bridge emission via Swift macro.
