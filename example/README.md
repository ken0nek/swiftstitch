# Examples

Two layers, by convention:

1. **Per-package codegen example** — one directory per package, focused on
   that package's input → output. Cheap (no native build), pairs 1:1 with
   the per-package README.
2. **One shared RN app** — runtime demo that imports the artifacts the
   codegen examples produce. All native build pain (Metro / Pod / Gradle /
   NDK) lives in this single place.

## Layout

| Directory | Layer | Status |
|---|---|---|
| [`nitrogen-swift-input/`](nitrogen-swift-input/) | codegen | ✅ runnable |
| [`counter-module/`](counter-module/) | module — a real consumable nitro package (Swift iOS + Kotlin Android), spec authored in Swift | ✅ real |
| [`rn-app/`](rn-app/) | runtime — consumes `counter-module` | ✅ runnable |
| [`nitrogen-swift-bridgejs/`](nitrogen-swift-bridgejs/) | codegen | 🚧 stub |
| [`nitrogen-swift-spec-input/`](nitrogen-swift-spec-input/) | codegen | 🚧 stub |
| [`nitrogen-swift-runtime/`](nitrogen-swift-runtime/) | codegen | 🚧 stub |
| [`nitrogen-swift-embedded/`](nitrogen-swift-embedded/) | codegen | 🚧 stub |
| [`swiftstitch/`](swiftstitch/) | codegen (top-level CLI) | 🚧 stub |

🚧 = becomes runnable when its package lands in `packages/`.

## Why this split

- Codegen examples don't need React Native, CocoaPods, or Gradle — just
  Bun + Swift. Running `./run.sh` in any of them is an exercise of the
  *codegen* surface, not a runtime test.
- A runtime example needs all of the above. Owning one (instead of six)
  keeps the maintenance surface manageable, mirrors upstream nitro's
  convention, and lets a single `App.tsx` exercise every front-end path.

## Picking which one to read

| If you want to… | Read |
|---|---|
| Author the spec in standard Swift | [`nitrogen-swift-input/`](nitrogen-swift-input/) |
| See a complete, consumable module package (podspec + gradle + generated trees committed) | [`counter-module/`](counter-module/) |
| Already run BridgeJS, want to feed its IR into nitrogen | [`nitrogen-swift-bridgejs/`](nitrogen-swift-bridgejs/) |
| Skip the `.nitro.ts` artifact entirely | [`nitrogen-swift-spec-input/`](nitrogen-swift-spec-input/) |
| Use the `@HybridObject(...)` macro on Swift 6.3+ | [`nitrogen-swift-runtime/`](nitrogen-swift-runtime/) |
| Ship Swift on Android with no Swift runtime in the APK | [`nitrogen-swift-embedded/`](nitrogen-swift-embedded/) |
| Run everything with one command | [`swiftstitch/`](swiftstitch/) |
| See it actually run inside an RN app | [`rn-app/`](rn-app/) |

## Pairings worth flagging

A couple of packages take similar inputs and diverge by one annotation /
flag:

- `nitrogen-swift-input` ↔ `nitrogen-swift-runtime` — both consume
  `Hybrid<Name>.swift`. The macro variant adds `@HybridObject(...)` and
  emits the C-bridge as peer decls instead of a `+CBridge.swift` file.
- `nitrogen-swift-input` ↔ `nitrogen-swift-spec-input` — the spec-input
  example *consumes* the IR JSON the input example *produces*. They chain
  rather than compete.

These have separate dirs today for narrative clarity. If two examples turn
out to be 90% the same file when they migrate, fold them into one with two
variants — don't keep duplicate scaffolding.
