# SwiftStitch

A Nitro Modules ecosystem plugin for first-class Swift across the authoring,
codegen, and Android packaging pipeline. Author `Hybrid<Name>` Swift
directly; SwiftStitch produces the spec, the bridge, and the Android `.so` —
with no `.nitro.ts` artifact and no Swift runtime in the APK by default.

Position: satellite plugin to [`mrousavy/nitro`](https://github.com/mrousavy/nitro).
Builds on top of nitrogen's released output. Does not patch nitrogen core.

## Packages

The packages below compose the pipeline. Each has its own toolchain floor
and a focused role; you only need the ones that match your front-end /
target platform.

| Package | Use case (write this when…) | Min toolchain | Prepare | Generates | Status |
|---|---|---|---|---|---|
| [`nitrogen-swift-input`](packages/nitrogen-swift-input/) | …you author the spec in standard Swift, no annotations | Swift 5.10+ | `Hybrid<Name>.swift` | `<Name>.nitro.ts` + IR JSON | ✅ shipped |
| `nitrogen-swift-bridgejs` | …you already run JavaScriptKit's BridgeJS and want to feed its IR into nitrogen | Bun 1.x (no Swift) | `BridgeJS.json` | `<Name>.nitro.ts` | 🚧 migrating |
| `nitrogen-swift-spec-input` | …you want to skip the `.nitro.ts` artifact and feed IR JSON straight into nitrogen | Bun 1.x | IR JSON (`.ir.json`) | `nitrogen/generated/` (in-process, no `.nitro.ts`) | 🚧 migrating |
| `nitrogen-swift-runtime` | …you're on Swift 6.3+ and want a `@HybridObject(ios:android:)` macro to emit the C bridge inline (no `+CBridge.swift` artifact) | Swift 6.3.1 | `Hybrid<Name>.swift` with `@HybridObject(...)` | `@c(<C-name>)` peer functions (compile-time) | 🚧 migrating |
| [`nitrogen-swift-embedded`](packages/nitrogen-swift-embedded/) | …you want first-class Swift on Android with no Swift stdlib in the APK | Swift 6.3.1 + Android NDK r27+ | IR JSON + user Swift impl dir | `+CBridge.swift`, `Hybrid<Foo>.hpp`, Embedded `.o` | ✅ shipped |
| [`swiftstitch`](packages/swiftstitch/) | …you want a single CLI that wraps `bunx nitrogen` + the Android alongside-pass | Bun 1.x, TypeScript 5 | Existing nitro project (`nitro.json` + sources) | Coordinated end-to-end run | ✅ shipped |

🚧 = not yet in this repo — lands as its package migrates in.

`nitrogen-swift-embedded` ships the codegen, the Embedded-Swift compile step,
and the Android alongside-pass that drives them (`nitrogen-swift-embedded
alongside`). `swiftstitch build` chains the whole pipeline —
`nitrogen-swift-input emit` → `bunx nitrogen` → `alongside` — in one command;
see [`packages/swiftstitch/RUNBOOK.md`](packages/swiftstitch/RUNBOOK.md). The
alongside-pass does **not** live in `nitrogen-swift-spec-input`, which is
untouched v0.3 work.

## Picking a pipeline

Decide three things, in this order:

### 1. Where does the spec come from?

| You write | Use front-end |
|---|---|
| `Hybrid<Name>.swift` (no annotations) | `nitrogen-swift-input` |
| `@JS`-annotated Swift, already emit BridgeJS IR | `nitrogen-swift-bridgejs` |
| `.nitro.ts` by hand | None — vanilla `bun nitrogen` |

### 2. Do you want the `.nitro.ts` artifact?

| Front-end output | Then |
|---|---|
| IR JSON (`<Name>.ir.json` — emitted by default, or alone via `--out-json <dir>`) — skip `.nitro.ts` | `nitrogen-swift-spec-input` (migrating) |
| `.nitro.ts` (emitted by default, or alone via `--out <dir>`) | `bun nitrogen` reads it |

### 3. What's the Android implementation language?

| `nitro.json` `android.language` | Behavior |
|---|---|
| `kotlin` | Stock nitrogen flow. Kotlin code + JNI. |
| `c++` | Stock nitrogen flow. User authors `Hybrid<Foo>.hpp`. |
| `swift` | **Not a value you write** — stock nitrogen rejects it. Declare `c++` and opt in with a `swiftstitch` block in `nitro.json`; the alongside-pass then emits the `@c` bridge + C++ glue + a CMake recipe, and the native build runs `swiftc` in Embedded mode. No Swift runtime in `jniLibs`. Requires the `nitrogen-swift-embedded` toolchain (Swift 6.3+ + NDK r27+) at native build time. |

## Quickstart

```sh
bun install                                                  # populates node_modules/.bin/nitrogen
swift build --package-path packages/nitrogen-swift-input
swift test  --package-path packages/nitrogen-swift-input
```

`./scripts/ci-local.sh` runs the suites for every Swift package plus the
`swiftstitch` TypeScript package in one go, and exits non-zero if any fails.
It leads with a toolchain preflight, because `nitrogen-swift-embedded`'s
compile and end-to-end tests **skip** when Swift 6.3+ or the Android NDK are
missing — so a green run on a machine without them has exercised less than a
green run on a machine with them.

The CLI favors zero-flag defaults: `nitrogen-swift-input init <Name>`
scaffolds `swift/Hybrid<Name>.swift` and chains into a first emit;
`nitrogen-swift-input emit` globs `swift/Hybrid*.swift`, writes
`specs/<Name>.nitro.ts` + `<Name>.ir.json`, and reads per-spec platforms
from `nitro.json` autolinking. See
[`packages/nitrogen-swift-input/`](packages/nitrogen-swift-input/) for the
full CLI surface.

Then walk through the end-to-end pipeline:

```sh
example/nitrogen-swift-input/run.sh
```

See [`example/nitrogen-swift-input/`](example/nitrogen-swift-input/) — a
`HybridCounter` taken from Swift source all the way to the generated
C++/Swift bridge.

## Examples

Two layers, by convention — see [`example/README.md`](example/README.md):

- **Per-package codegen examples** — one dir per package
  ([`example/nitrogen-swift-*/`](example/)), focused on that package's
  input → output. Cheap, no native build.
- **One shared RN app** ([`example/rn-app/`](example/rn-app/)) — runtime
  demo that imports the codegen output. All native build pain
  (Metro / Pod / Gradle / NDK) lives here.

Runnable today: [`example/nitrogen-swift-input/`](example/nitrogen-swift-input/)
(the codegen walkthrough), [`example/counter-module/`](example/counter-module/)
(a real consumable nitro module authored in Swift — iOS Swift + Android
Kotlin), [`example/math-module/`](example/math-module/) (the same idea with
Android in Swift too, via Embedded Swift — the parity bar's subject), and
[`example/rn-app/`](example/rn-app/) (the RN app that consumes both). The
remaining per-package dirs are stubs that flip on as their packages migrate.

## Parity bar

`example/math-module` is a Swift-on-Android module — one Swift file is both the
spec source *and* the Android implementation, with no hand-written Kotlin or
C++. `scripts/parity-bar.sh` drives it through the full plugin pipeline into a
debug APK and proves two things a unit-test suite cannot:

- the shipped `lib/arm64-v8a/libNitroMath.so` has **no `libswift*` and no
  Foundation entry** in its `DT_NEEDED` — no Swift runtime in the APK — and
  everything it does carry is either bionic (`libc.so`, `libm.so`, `libdl.so`,
  `liblog.so`, `libandroid.so`, `libc++_shared.so`) or one of the React Native
  / Nitro shared libraries every nitro module links (`libNitroModules.so`,
  `libfbjni.so`, `libjsi.so`, `libreactnative.so`);
- the module answers a real JS call correctly — verified by installing the
  APK on a live emulator and reading the result back from `logcat`.

**Known gap — the same file does not also compile for iOS.** `nitro.json`
declares `ios.language: "swift"`, so nitrogen does generate the iOS sources
from this spec, but `swift/HybridSimpleMath.swift` is a bare class: it does not
inherit the generated `HybridSimpleMathSpec`, so nitrogen's iOS autolinking
(which calls `getCxxWrapper()` on it) would not compile against it. The two
shapes are mutually exclusive today — iOS needs the class to inherit the
generated spec from inside `#if canImport(NitroModules)`, and under Embedded
Swift that guard is false, so the class would vanish and the bridge's
`HybridSimpleMath_create()` would have nothing left to construct. Nothing is
broken by this: the module ships no podspec, its `react-native.config.js`
declares Android only, and the parity bar is Android-only.
[`example/counter-module`](example/counter-module/) is the worked
Swift-on-iOS reference.

```sh
./scripts/parity-bar.sh
```

Stage 1 regenerates three committed trees in `example/math-module` in place:
`specs/` (the IR), `nitrogen/generated/` (nitrogen's own output), and
`swiftstitch/generated/` (the alongside pass's Swift bridge, C++ glue header,
and CMake fragment — deliberately outside nitrogen's tree, which nitrogen
sweeps clean of anything it did not itself write). The output is byte-identical,
so `git status` stays clean after a run — if it does not, the codegen changed
and that diff is the finding.

Deliberately **not** part of `./scripts/ci-local.sh` — it needs Gradle, the
Android NDK, and a booted emulator, none of which `ci-local.sh` requires.
Prerequisites, checked by its own preflight (which fails fast, naming
whichever is missing):

- Swift 6.3.1 toolchain
- Android NDK r27+ (for `llvm-readelf`)
- `adb` on `PATH`
- a JDK 21 to run Gradle itself (resolved via `mise where java`, falling
  back to Android Studio's bundled JBR)
- a **JDK 17**, separate from the JDK 21 above. React Native's Gradle
  plugin's own included build declares `kotlin { jvmToolchain(17) }` and
  compiles before, and independently of, anything this project sets.
  Without a JDK 17 already installed, Gradle's toolchain auto-provisioning
  crashes instead of fetching one (the pinned `foojay-resolver-convention`
  0.5.0 is incompatible with newer Gradle). Install one with
  `mise install java@temurin-17` — **not** `mise use`, which would rewrite
  this repo's committed `.mise.toml` pin from `temurin-21` to `temurin-17`
  and change the JDK that runs Gradle itself. The parity bar discovers the
  JDK 17 and hands it to Gradle via
  `-Porg.gradle.java.installations.paths`; it does not need to be the
  active pin.
- an arm64-v8a AVD (checked by reading its `config.ini`, not its name)

**Building the example app directly**, outside the parity bar, needs one
more flag that is recorded only here. `example/rn-app/android/gradle.properties`
declares `reactNativeArchitectures=armeabi-v7a,arm64-v8a,x86,x86_64`, but the
CMake fragment SwiftStitch generates for Swift-on-Android recognizes only
three ABI triples and `message(FATAL_ERROR)`s on any other — `x86` is not
among them. A plain `./gradlew :app:assembleDebug` therefore fails
configuring `x86` before an arm64 binary is ever produced. Restrict the
build on the command line instead of editing the committed
`gradle.properties`:

```sh
./gradlew :app:assembleDebug -PreactNativeArchitectures=arm64-v8a \
  -Porg.gradle.java.installations.paths=/path/to/jdk-17
```

The second flag registers the JDK 17 from the prerequisites above as a
toolchain Gradle can discover; without it, Gradle tries to auto-provision one
and crashes rather than fetching it. `scripts/parity-bar.sh` passes both flags
itself, resolving the JDK 17 path in its preflight.

## Toolchain summary

| Component | Min |
|---|---|
| Bun | 1.x |
| Swift (codegen host) | 5.10+ — `swift-syntax` 510.x. |
| Swift (codegen host, Phase 2C/2D) | 6.3.1 — `nitrogen-swift-embedded` and `nitrogen-swift-runtime` use 6.3-only features (`@c`, Embedded mode). |
| Android NDK | r27+ — only if you opt into `android: 'swift'`. |

Per-package toolchain floors are listed in the table at the top.

## Working principles

- **Minimal critical changes. Ship working increments.** No drive-by
  refactors. No scaffolding for hypothetical future needs.
- **Plugin posture, not fork:** never patch `react-native-nitro-modules`
  directly. Wrap what nitrogen already emits.
- **Spec-input first:** prefer the IR-JSON path (no `.nitro.ts` artifact) to
  in-process nitrogen entry points or upstream-API additions.
- **Alongside-pass over schema changes:** for Swift-on-Android, the user-facing
  `SwiftHybridObject` wrapper resolves to nitrogen's existing `'c++'` Android
  value, and a post-`bun nitrogen` step replaces the C++ stub with Swift glue.

## Docs

Docs live next to the code: each package ships a README (executive summary)
plus a `RUNBOOK.md` covering CLI semantics, architecture, and the test
surface — see [`packages/nitrogen-swift-input/`](packages/nitrogen-swift-input/)
and [`packages/nitrogen-swift-embedded/`](packages/nitrogen-swift-embedded/)
for the shipped ones, and [`example/README.md`](example/README.md) for the
example layout.
