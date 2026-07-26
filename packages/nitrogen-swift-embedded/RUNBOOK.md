# `nitrogen-swift-embedded` — runbook

**What it does.** Swift CLI that turns IR JSON into the Phase 2C glue files and drives `swiftc` in Embedded mode to produce a no-runtime `.o` for Android. Three subcommands:

- `emit` — generates `<Class>+CBridge.swift` (Swift `@c` shims).
- `emit-cpp` — generates `<Class>.hpp` (C++ subclass of `<Class>Spec` that forwards to the `@c` symbols).
- `compile` — runs `swiftc -target *-none-none-elf -enable-experimental-feature Embedded` to produce the Android-NDK-linkable `.o`.

**When to use it.** You're shipping Swift on Android without the Swift runtime in `jniLibs/`. With Phase 2C wired into nitrogen autolinking, end users typically don't invoke this CLI directly — `bun nitro` writes the bridge `.swift` and the CMake fragment handles `compile` at native-build time. This CLI is what you use:

- For one-off integration / CI / smoke tests.
- For projects that haven't adopted nitrogen's autolinking but still want the Phase 2C output shape.
- For producing the artifacts the `EndToEndIntegrationTests` exercise.

## Toolchain

- **Swift 6.2+** to build this package (the CLI itself).
- **Swift 6.3+** at runtime — `compile` requires Embedded Swift mode (`-enable-experimental-feature Embedded`) and the `@c` attribute (`-enable-experimental-feature CImplementation`), both of which shipped in Swift 6.3. Install via `swiftly install 6.3.1`.
- **Android NDK r27+** for the final link step (not invoked by this CLI — link your `.o` with NDK clang).

## Build

```bash
cd packages/nitrogen-swift-embedded
swift build
# or
swift build -c release
```

Binary lands at `.build/debug/nitrogen-swift-embedded`.

## CLI

### `emit` — Swift `@c` bridge

```
nitrogen-swift-embedded emit
  --ir <ir.json>
  --out <dir>
```

Reads the IR JSON, emits `<Class>+CBridge.swift` per HybridObject into `<dir>`. Each emitted file declares:

- `@c func <Class>_create() -> UnsafeMutableRawPointer`
- `@c func <Class>_destroy(handle:)`
- `@c func <Class>_<method>(handle, args...) -> ReturnType` per spec method

`@c` (Swift 6.3) gives the function a stable C-ABI symbol with no name mangling. `Unmanaged.passRetained` / `fromOpaque` round-trip the user's Swift class through an opaque `void*` handle.

### `emit-cpp` — C++ glue header

```
nitrogen-swift-embedded emit-cpp
  --ir <ir.json>
  --out <dir>
  --namespace <ns>     # e.g. margelo::nitro::test
```

Reads the IR JSON, emits `<Class>.hpp` per HybridObject. The header:

- `#include`s `<Class>Spec.hpp` (which nitrogen produces for the shared C++ layer).
- Declares `extern "C"` prototypes matching the `@c` shims emitted by `emit`.
- Defines a concrete `class <Class> : public virtual <Class>Spec` that owns a `void*` handle and overrides each virtual method by forwarding to the `@c` symbol.

### `compile` — Embedded Swift → `.o`

```
nitrogen-swift-embedded compile
  --ir <ir.json>
  --user-swift <path> [--user-swift <path> ...]
  --bridge-dir <dir>            # contains the +CBridge.swift files emitted by `emit`
  --out-o <path>
  [--arch aarch64|x86_64|armv7]
  --swiftc <path>               # path to a Swift 6.3+ swiftc
```

Runs `swiftc -target <arch>-none-none-elf -enable-experimental-feature Embedded -enable-experimental-feature CImplementation -wmo -parse-as-library -O -c -o <out>.o <user-swift>... <bridge>...`.

The choice of `*-none-none-elf` (bare-metal ELF, no OS) is deliberate — it produces no-runtime object code that the Android NDK can link directly into a host `.so`. The AAPCS/AAPCS64 calling conventions match what Android expects, so the only remaining undefined symbols are bionic primitives (`free`, `memmove`, `posix_memalign`, `__stack_chk_*`, `putchar`).

## End-to-end (one Hybrid)

For a `HybridSimpleMath.swift` whose IR JSON lives at `out/SimpleMath.ir.json`:

```bash
# 1. Generate the Swift @c bridge.
nitrogen-swift-embedded emit \
  --ir out/SimpleMath.ir.json \
  --out out/swift-embedded

# 2. Generate the C++ glue.
nitrogen-swift-embedded emit-cpp \
  --ir out/SimpleMath.ir.json \
  --out out/cpp-glue \
  --namespace margelo::nitro::demo

# 3. Compile to a no-runtime arm64 ELF .o.
nitrogen-swift-embedded compile \
  --ir out/SimpleMath.ir.json \
  --user-swift src/HybridSimpleMath.swift \
  --bridge-dir out/swift-embedded \
  --out-o out/HybridSimpleMath.o \
  --arch aarch64 \
  --swiftc ~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swiftc

# 4. Link into the host .so with the Android NDK (NOT done by this CLI).
~/Library/Android/sdk/ndk/27.1.12297006/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android28-clang++ \
  -shared -fPIC -O2 \
  -I out/cpp-glue -I out/shared/c++ \
  -o libNitroTest.so \
  host.cpp out/HybridSimpleMath.o
```

The resulting `.so` has only bionic + `libc++_shared` in `DT_NEEDED` — no `libswiftCore.so`, no Foundation overlay.

## Symbol contract

For a Hybrid named `HybridFoo` with method `bar(a: Double) -> Int64`:

| Symbol | Type |
|---|---|
| `HybridFoo_create` | `void* ()` |
| `HybridFoo_destroy` | `void (void*)` |
| `HybridFoo_bar` | `int64_t (void*, double)` |

C++ override widens `Float` to `double` in the method signature (matching nitrogen's `NumberType`), with a `static_cast` at the `@c` boundary. `void` returns map to `void`. Throwing methods are wrapped with `try!` for now — error propagation across the C ABI is a follow-up.

## Tests

```bash
swift test          # 15/15 expected
```

Coverage:
- `CBridgeEmitterTests` — golden files for `HybridSimpleMath` / `HybridMath` / `HybridTypes`, determinism check.
- `CppGlueEmitterTests` — golden + Float widening + void return + namespace shape.
- `EmbeddedCompilerTests` — actually invokes Swift 6.3+ swiftc and asserts a non-trivial `.o` is produced. Skips if the toolchain isn't installed.
- `CLITests` — end-to-end exercise of `emit`, `emit-cpp`, `compile` subcommands.
- `EndToEndIntegrationTests` — full pipeline through NDK link, asserting `DT_NEEDED` is bionic-only and the `@c` symbols are exported. Skips if Swift 6.3+ or NDK aren't present.

## Common errors

- *"swiftc not found at ..."* — `--swiftc` doesn't point at a real binary. Use the absolute path under `~/Library/Developer/Toolchains/...` or wherever swiftly puts it.
- *"unable to load standard library for target 'aarch64-unknown-linux-android28'"* — you're trying to use the Android SDK target with `-enable-experimental-feature Embedded`. Embedded mode requires a `*-none-none-elf` target instead. The `compile` subcommand uses the right target automatically; check your CLI args if you've overridden `--arch`.
- *"file not found: <Class>+CBridge.swift"* — `--bridge-dir` doesn't contain a bridge file matching the IR's class names. Run `emit` first.
- *"Phase 2C swift-embedded does not yet support type `string`"* — the IR uses a type outside Phase 2C's primitive subset. Stick to `Bool`/`Double`/`Int64`/`UInt64`/`Void` for now.

## Limitations (current 2C scope)

- Phase 2C primitive subset only — no `String`, `Array<T>`, `Optional<T>`, `struct`, `enum`, `async`, closures.
- Throwing methods abort via `try!` rather than propagating across the C ABI.
- Float widens to `double` in the C++ override (matches nitrogen `NumberType`); the Float→double conversion happens at the `@c` boundary.
- Targets `aarch64-none-none-elf`, `x86_64-unknown-none-elf`, `armv7-none-none-eabi`. Only `aarch64-none-none-elf` (Android arm64-v8a) has been live-tested on emulator.

## See also

- `../nitrogen-swift-input/WORKLOG.md` "Phase 2C" — design rationale and the live-emulator validation log.
- `../nitrogen-swift-spec-input/RUNBOOK.md` — the TS adapter that, when paired with nitrogen's `android: 'swift'` autolinking, makes `bun nitro` invoke this pipeline automatically at codegen + build time.
- `Tests/NitrogenSwiftEmbeddedCoreTests/EndToEndIntegrationTests.swift` — the strongest reproducer of the headline assertion.
