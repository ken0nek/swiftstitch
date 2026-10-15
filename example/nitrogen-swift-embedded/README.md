# Example: nitrogen-swift-embedded *(stub)*

🚧 **Not yet runnable.** The package itself has landed —
[`packages/nitrogen-swift-embedded/`](../../packages/nitrogen-swift-embedded/)
ships `emit` / `emit-cpp` / `compile` with its suite green. What's missing is
the walkthrough: this directory will hold a runnable one once there's a
harness that drives the CLI end to end without a full native build.

Until then, [that package's RUNBOOK](../../packages/nitrogen-swift-embedded/RUNBOOK.md)
carries a copy-pasteable worked example, and its `EndToEndIntegrationTests`
is the executable version of this walkthrough.

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
   │  nitrogen-swift-embedded emit   /   emit-cpp
   ▼
{Hybrid<Foo>+CBridge.swift,  Hybrid<Foo>.hpp}
   │  nitrogen-swift-embedded compile
   │  swiftc -target *-none-none-elf -enable-experimental-feature Embedded
   │         -enable-experimental-feature CImplementation -wmo -parse-as-library -c
   ▼
build/<abi>/Hybrid<Foo>.o
   │  Android NDK linker — you drive this; the CLI stops at the .o
   ▼
libMyApp.so   ← contains Embedded Swift code, links bionic + libc++_shared only
```

The CMake fragment that compiles and links the Embedded `.o` comes from this
same package's `alongside` subcommand, which writes the bridge, the C++ glue,
and the fragment to `swiftstitch/generated/`. See
[`example/math-module/`](../math-module/) for a module wired end to end.

| | |
|---|---|
| **Prepare** | IR JSON (from `nitrogen-swift-input` or `-bridgejs`) + the directory holding `Hybrid<Name>.swift` impl files. |
| **Generates** | `+CBridge.swift`, `Hybrid<Foo>.hpp`, and the `.o` per ABI. Not the CMake fragment. |
| **Min toolchain** | Swift 6.3.1 + Android NDK r27+. |
| **Runtime story** | Lives in [`../rn-app/`](../rn-app/) once that lands. |

The example will gate the NDK link step on toolchain detection, as the
package's own tests do: they carry `.enabled(if:)` traits and **skip** without
Swift 6.3+ and the NDK, so check `./scripts/ci-local.sh`'s preflight before
reading a green run as full coverage.

## Environment

| Env var | Purpose |
|---|---|
| `NITRO_SWIFTC` | Path to a Swift 6.3+ `swiftc` (typically a `.xctoolchain` install or swift-android-sdk). |
| `NITRO_USER_SWIFT_DIR` | Directory containing `Hybrid<Name>.swift` impls — passed at native build time. |

## See also

- [`packages/nitrogen-swift-embedded/`](../../packages/nitrogen-swift-embedded/) —
  the shipped package: [README](../../packages/nitrogen-swift-embedded/README.md)
  for the summary, [RUNBOOK](../../packages/nitrogen-swift-embedded/RUNBOOK.md)
  for the worked example and full CLI surface.
- [`../nitrogen-swift-runtime/`](../nitrogen-swift-runtime/) — alternative C-bridge emission via Swift macro.
