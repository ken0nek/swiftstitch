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
| `nitrogen-swift-embedded` | …you want first-class Swift on Android with no Swift stdlib in the APK | Swift 6.3.1 + Android NDK r27+ | IR JSON + user Swift impl dir | `+CBridge.swift`, `Hybrid<Foo>.hpp`, Embedded `.o` | 🚧 migrating |
| `swiftstitch` | …you want a single CLI that wraps `bun nitrogen` + the Android alongside-pass | Bun 1.x, TypeScript 5 | Existing nitro project (`nitro.json` + sources) | Coordinated end-to-end run | 🚧 planned |

🚧 = not yet in this repo — lands as its package migrates in.

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
| `swift` | SwiftStitch alongside-pass: nitrogen emits `@c` bridge + C++ glue + a CMake recipe; build time runs `swiftc` in Embedded mode. No Swift runtime in `jniLibs`. Requires `nitrogen-swift-embedded` toolchain (Swift 6.3+ + NDK r27+) at native build time. *(Currently rejected by stock nitrogen — `swiftstitch` wraps the existing `'c++'` value to keep schema unchanged.)* |

## Quickstart

```sh
bun install                                                  # populates node_modules/.bin/nitrogen
swift build --package-path packages/nitrogen-swift-input
swift test  --package-path packages/nitrogen-swift-input
```

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
Kotlin), and [`example/rn-app/`](example/rn-app/) (the RN app that consumes
it). The remaining per-package dirs are stubs that flip on as their packages
migrate.

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
for the shipped one, and [`example/README.md`](example/README.md) for the
example layout.
