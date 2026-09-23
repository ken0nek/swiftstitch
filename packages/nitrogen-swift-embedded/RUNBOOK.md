# `nitrogen-swift-embedded` — runbook

## What you actually do

In a nitro module with a [`swiftstitch` block](#the-swiftstitch-block) in its
`nitro.json`, one command after `bunx nitrogen` writes everything Swift-on-Android
needs:

```bash
bunx nitrogen
nitrogen-swift-embedded alongside --nitro-json nitro.json
```

Add the [one `include` line](#the-one-line-you-add) to your `android/CMakeLists.txt`,
export `NITRO_SWIFTC`, and `./gradlew assembleDebug` compiles your Swift into the
host `.so`. That is the whole story — see [`alongside`](#alongside--the-post-nitrogen-pass).

The three lower-level subcommands are what `alongside` (and the CMake fragment it
writes) run on your behalf. Reach for them directly only for one-off integration
work, or in a project that hasn't adopted the block. Given a `Hybrid<Name>.swift`
and its IR JSON, they produce an Android-linkable object file with no Swift
runtime:

```bash
nitrogen-swift-embedded emit      --ir out/Name.ir.json --out out/swift-embedded
nitrogen-swift-embedded emit-cpp  --ir out/Name.ir.json --out out/cpp-glue --namespace margelo::nitro::demo
nitrogen-swift-embedded compile   --ir out/Name.ir.json \
  --user-swift src/HybridName.swift --bridge-dir out/swift-embedded \
  --out-o out/HybridName.o --arch aarch64 \
  --swiftc ~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swiftc
```

You then link `out/HybridName.o` into your host `.so` with NDK clang — this CLI
does not do the link. Full worked example under
[End-to-end (one Hybrid)](#end-to-end-one-hybrid).

**What it does.** Swift CLI that turns IR JSON into the Phase 2C glue files and drives `swiftc` in Embedded mode to produce a no-runtime `.o` for Android. Four subcommands:

- `emit` — generates `<Class>+CBridge.swift` (Swift `@c` shims).
- `emit-cpp` — generates `<Class>.hpp` (C++ subclass of `<Class>Spec` that forwards to the `@c` symbols).
- `compile` — runs `swiftc -target *-none-none-elf -enable-experimental-feature Embedded` to produce the Android-NDK-linkable `.o`.
- `alongside` — the post-`bunx nitrogen` pass: does `emit` + `emit-cpp` for every spec the `swiftstitch` block names, into `swiftstitch/generated/`, and writes a CMake fragment that runs `compile`'s equivalent at native-build time.

**When to use it.** You're shipping Swift on Android without the Swift runtime in `jniLibs/`. `alongside` is the front door and the only subcommand a module author normally runs. The other three are what you use:

- For one-off integration / CI / smoke tests.
- For projects that haven't adopted the `swiftstitch` block but still want the Phase 2C output shape.
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

Runs `swiftc -target <arch>-none-none-elf -enable-experimental-feature Embedded -enable-experimental-feature CImplementation -wmo -parse-as-library -c -o <out>.o <user-swift>... <bridge>...`.

The choice of `*-none-none-elf` (bare-metal ELF, no OS) is deliberate — it produces no-runtime object code that the Android NDK can link directly into a host `.so`. The AAPCS/AAPCS64 calling conventions match what Android expects, so the only remaining undefined symbols are bionic primitives (`free`, `memmove`, `posix_memalign`, `__stack_chk_*`, `putchar`).

### `alongside` — the post-nitrogen pass

```
nitrogen-swift-embedded alongside
  --nitro-json <path>        # the module's nitro.json
  [--out-dir <dir>]          # default: swiftstitch/generated
  [--ir-dir <dir>]           # default: specs/
```

Both directory flags default to a module-relative convention and are resolved
against `nitro.json`'s own directory, not your cwd — so the one required flag
is enough from anywhere.

Run it **after** `bunx nitrogen`, from anywhere. When a spec declares
`android: 'c++'`, nitrogen emits the shared C++ layer plus an
`#include "Hybrid<Foo>.hpp"` in `<Lib>OnLoad.cpp`, then deliberately leaves the
implementation to you. There is no stub to overwrite — the definition simply
doesn't exist. `alongside` writes exactly that missing piece, so all you author
is `Hybrid<Foo>.swift`.

The pass only ever **creates** files, at the three paths below, all inside its
own `swiftstitch/generated/` tree. It neither reads nor writes anything under
`nitrogen/generated/`, so it cannot corrupt nitrogen's output — and nitrogen's
cleanup, which is scoped to that directory, cannot delete ours. See
[Your outputs survive a bare `bunx nitrogen`](#your-outputs-survive-a-bare-bunx-nitrogen).

#### The `swiftstitch` block

Opt-in is explicit, and lives in `nitro.json`. Nitrogen strips unknown
top-level keys at parse, so the block is invisible to it:

```jsonc
{
  "$schema": "https://nitro.margelo.com/nitro.schema.json",
  "cxxNamespace": ["embedded"],
  "ios": { "iosModuleName": "EmbeddedTest" },
  "android": { "androidNamespace": ["embedded"], "androidCxxLibName": "EmbeddedTest" },
  "autolinking": {
    "SimpleMath": {
      "ios":     { "language": "swift", "implementationClassName": "HybridSimpleMath" },
      "android": { "language": "c++",   "implementationClassName": "HybridSimpleMath" }
    }
  },

  "swiftstitch": {
    "userSwiftDir": "swift",
    "swiftOnAndroid": ["SimpleMath"]
  }
}
```

Both keys are required when the block is present. `swiftOnAndroid` holds **spec
names** (the `autolinking` keys), not class names — the class comes from that
spec's `android.implementationClassName`, and the pass never derives one from
the other. Android language must be `"c++"`: that is what nitrogen accepts, and
the Swift arrives underneath it.

**No block means no-op, exit 0.** iOS-only authors run the same command.

#### What it writes

For `androidCxxLibName: "EmbeddedTest"` and class `HybridSimpleMath`:

```
swiftstitch/generated/swift/HybridSimpleMath+CBridge.swift
swiftstitch/generated/c++/HybridSimpleMath.hpp
swiftstitch/generated/EmbeddedTest+swift-embedded.cmake
```

The tree is flat because all of it is ours and this pass is Android-only —
iOS goes through nitrogen's own Swift output, never through here.

`swiftstitch/generated/c++/` is *not* on nitrogen's `include_directories`,
so the CMake fragment adds it with a `target_include_directories(...)` line
of its own. That is what makes the `#include "HybridSimpleMath.hpp"` nitrogen
emits unprompted into `<Lib>OnLoad.cpp` resolve; it comes for free with the
include you already add.

Re-running is byte-identical — the emitters are deterministic, so there is no
"already exists" check to defeat.

#### The one line you add

The fragment ends in `target_sources(<androidCxxLibName> PRIVATE ...)`, which
executes at include time, so **`add_library` must already have run**. Both
includes go after it, in this order:

```cmake
add_library(${PACKAGE_NAME} SHARED src/main/cpp/cpp-adapter.cpp)

include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/EmbeddedTest+autolinking.cmake)
include(${CMAKE_SOURCE_DIR}/../swiftstitch/generated/EmbeddedTest+swift-embedded.cmake)
```

Note the second path is **not** under `nitrogen/generated/` — see below for why
that matters. Ordering between the two includes is a `target_sources`
requirement only: `add_library` must have run. The fragment's
`target_include_directories` is a target property, resolved at generate time,
so it reaches the autolinking sources added before it regardless of order.

A separate fragment rather than an append to nitrogen's `+autolinking.cmake`:
that file is headed `DO NOT MODIFY THIS FILE` and is rewritten every run, so an
append would be discarded.

#### Your outputs survive a bare `bunx nitrogen`

Nitrogen's CLI deletes every file under **its own output directory** that it did
not itself generate on that run — it snapshots `nitrogen/generated/` recursively
beforehand and `fs.rm`s the leftovers, with no allowlist. Anything of ours placed
in there is erased, whether appended to a nitrogen file or sitting in a separate
one of its own.

That is exactly why the three files above live in `swiftstitch/generated/`
instead. The sweep is scoped to `nitrogen/generated/` and does not reach a
sibling directory, so a bare `bunx nitrogen` leaves all three in place and the
next native build still finds the fragment, the bridge, and the header.
Verified empirically against nitrogen 0.36.1, and re-verified against 0.37.1
(`node_modules/nitrogen/lib/index.js`,
`node_modules/nitrogen/lib/getFiles.js`) with planted canary files: one nested
under `nitrogen/generated/` was deleted, one in a sibling directory was not.

Re-running `alongside` after `bunx nitrogen` is still the right habit — the IR
may have changed — but it is no longer load-bearing for the files' existence.
`swiftstitch build` does both in one invocation.

#### `NITRO_SWIFTC`

The fragment reads one environment variable, and hard-fails at CMake configure
time without it:

```bash
export NITRO_SWIFTC=~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swiftc
```

> `swift-embedded: NITRO_SWIFTC must point at a Swift 6.3+ swiftc.`

It stays an env var because the toolchain path is per-machine. `userSwiftDir` is
by contrast baked into the fragment at generate time — it is a `nitro.json`
value, so making the build depend on shell state for it would be gratuitous.

Compilation happens at native-build time rather than in this pass, which buys
per-ABI targeting for free (`ANDROID_ABI` selects the `*-none-elf` triple) and
correct incremental rebuilds via `DEPENDS` on your `.swift` files.

#### Errors

| Condition | Behavior |
|---|---|
| No `swiftstitch` block | no-op, exit 0 |
| Listed spec absent from `autolinking` | hard error naming the key |
| Listed spec's `android.language != "c++"` | hard error stating the required value |
| IR JSON missing | hard error naming the expected path |
| `Hybrid<Class>.swift` missing under `userSwiftDir` | hard error naming the expected path |
| `NITRO_SWIFTC` unset | CMake `FATAL_ERROR`, at build time |

Everything is resolved and emitted in memory before the first write, so a
failure halfway through leaves no half-written tree behind.

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
swift test          # 23/23 expected
```

Coverage:
- `CBridgeEmitterTests` — golden files for `HybridSimpleMath` / `HybridMath` / `HybridTypes`, determinism check.
- `CppGlueEmitterTests` — golden + Float widening + void return + namespace shape.
- `AlongsideTests` — the `alongside` pass over a scratch module: the three
  contracted paths, CMake fragment shape, byte-identical re-runs, and each
  error in the table above. Needs no toolchain, so it always runs.
- `EmbeddedCompilerTests` — actually invokes Swift 6.3+ swiftc and asserts a
  non-trivial `.o` is produced.
- `CLITests` — end-to-end exercise of `emit`, `emit-cpp`, `compile` subcommands.
- `EndToEndIntegrationTests` — full pipeline through NDK link, asserting
  `DT_NEEDED` is bionic-only and the `@c` symbols are exported.

The toolchain-dependent tests carry `.enabled(if:)` traits and **skip** without
Swift 6.3+ / NDK r27+, so a smaller run on a bare machine is not a regression.
Treat "23/23" as a claim about a machine with both installed.

## Common errors

- *"swiftc not found at ..."* — `--swiftc` doesn't point at a real binary. Use the absolute path under `~/Library/Developer/Toolchains/...` or wherever swiftly puts it.
- *"unable to load standard library for target 'aarch64-unknown-linux-android28'"* — you're trying to use the Android SDK target with `-enable-experimental-feature Embedded`. Embedded mode requires a `*-none-none-elf` target instead. The `compile` subcommand uses the right target automatically; check your CLI args if you've overridden `--arch`.
- *"file not found: <Class>+CBridge.swift"* — `--bridge-dir` doesn't contain a bridge file matching the IR's class names. Run `emit` first.
- *"Phase 2C swift-embedded does not yet support type `string`"* — the IR uses a type outside Phase 2C's primitive subset. Stick to `Bool`/`Double`/`Int64`/`UInt64`/`Void` for now.
- *The toolchain-gated tests skip, when the toolchain "is installed"* — the
  probe tries exactly two paths, `swift-6.3.1-RELEASE` then
  `swift-6.3.0-RELEASE`, both under `~/Library/Developer/Toolchains/`. It does
  **not** consult `swift-latest.xctoolchain` (that symlink can resolve below
  6.3, which would make the probe report a false positive) and it does not
  search `$PATH` or `xcrun`. A 6.3.x toolchain installed anywhere else is
  invisible to it, and the tests skip silently. Pass `--swiftc` explicitly when
  invoking the CLI; for the tests, install to one of the two paths above.

## Limitations (current 2C scope)

- Phase 2C primitive subset only — no `String`, `Array<T>`, `Optional<T>`, `struct`, `enum`, `async`, closures.
- **`try!` error propagation is broken.** `CBridgeEmitter` wraps a throwing
  method's call in `try!`, so a Swift method that throws **traps and kills the
  process** rather than surfacing the error to JS as a rejected promise. The C
  ABI carries no error channel yet. Avoid `throws` on Hybrid methods you ship on
  Android until this lands; it is a tracked v0.2 follow-up, deliberately not
  fixed by the alongside pass.
- Float widens to `double` in the C++ override (matches nitrogen `NumberType`); the Float→double conversion happens at the `@c` boundary.
- Targets `aarch64-none-none-elf`, `x86_64-unknown-none-elf`, `armv7-none-none-eabi`. Only `aarch64-none-none-elf` (Android arm64-v8a) is exercised by the test suite, which takes it through the Embedded Swift compile, an NDK link, and the `DT_NEEDED` / exported-symbol assertions. The other two triples are emitted by `CMakeFragmentEmitter` but have no test.
- **Nothing in this project has run on a device or emulator yet.** The
  no-Swift-runtime claim rests on object- and link-level evidence — see
  `EndToEndIntegrationTests` — not on a shipped, launched app.
  `scripts/parity-bar.sh` is the gate that would close that gap; it has never
  run past its JDK 17 preflight.

## See also

- [`../nitrogen-swift-input/RUNBOOK.md`](../nitrogen-swift-input/RUNBOOK.md) —
  the front end that produces the IR JSON this package consumes.
- `Tests/NitrogenSwiftEmbeddedCoreTests/EndToEndIntegrationTests.swift` — the
  strongest reproducer of the no-Swift-runtime assertion.
- [`alongside`](#alongside--the-post-nitrogen-pass) — the pass that drives this
  pipeline off `nitro.json` instead of hand-run subcommands.
