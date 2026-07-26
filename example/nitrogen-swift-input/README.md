# Example: end-to-end Hybrid Object pipeline

A small `Counter` HybridObject taken all the way from a Swift source file to
the generated C++/Swift bridge that nitrogen ships to Xcode. Two stages,
one command, no native build step.

```
swift/HybridCounter.swift
   │  ① nitrogen-swift-input emit              (this repo's CLI — SwiftSyntax-only parse)
   ▼
specs/Counter.nitro.ts        + specs/Counter.ir.json
   │  ② bun nitrogen specs                     (stock nitrogen)
   ▼
nitrogen/generated/{shared,ios}/...
```

`./run.sh` runs both stages from a clean state. Re-run any time you edit
`swift/HybridCounter.swift` or `nitro.json`.

## Layout

| Path | Role |
|---|---|
| `swift/HybridCounter.swift` | What the developer authors. Single file — both the spec source for stage ① and the runtime impl that compiles after stage ②. |
| `nitro.json` | Stock nitrogen config (autolinking + module names). Stage ② reads this. |
| `run.sh` | Driver — wipes prior outputs, runs ①, runs ②, prints the generated tree. |
| `specs/` *(generated)* | Stage ① outputs: `Counter.nitro.ts` (nitrogen's input) + `Counter.ir.json` (schema v1, for downstream tooling). |
| `nitrogen/generated/` *(generated)* | Stage ② outputs: shared C++ spec, iOS Swift spec, autolinking glue. |

`specs/` and `nitrogen/` are gitignored — the canonical state lives in
`swift/` and `nitro.json`.

## Run it

Prerequisites — once per checkout:

```sh
bun install                                            # populates node_modules/.bin/nitrogen
swift build --package-path packages/nitrogen-swift-input
```

Then, from anywhere:

```sh
example/nitrogen-swift-input/run.sh
```

`run.sh` rebuilds the SwiftPM CLI on demand if it isn't already built.

## What stage ① emits

Given `swift/HybridCounter.swift`, `nitrogen-swift-input emit` produces:

`specs/Counter.nitro.ts` — what stock nitrogen consumes:

```ts
import type { HybridObject, Int64 } from 'react-native-nitro-modules'

export interface Counter extends HybridObject<{ ios: 'swift' }> {
  increment(): void
  reset(): void
  value(): Int64
  add(delta: Int64): Int64
}
```

`specs/Counter.ir.json` — the same shape in machine-readable form
(schema v1). Reserved for the downstream `nitrogen-swift-spec-input`
adapter, which will skip the `.nitro.ts` artifact entirely. For now it's a useful
debugging artifact: it round-trips `isThrowing` and parameter labels that
the TS interface format throws away.

## What stage ② emits

`bun nitrogen specs` reads `nitro.json` + `specs/Counter.nitro.ts` and emits
13 files under `nitrogen/generated/`:

```
nitrogen/generated/
├── .gitattributes
├── shared/c++/HybridCounterSpec.{hpp,cpp}        ← cross-platform C++ abstract base
└── ios/
    ├── swift/HybridCounterSpec.swift             ← protocol + open base, typealias'd
    ├── swift/HybridCounterSpec_cxx.swift         ← Swift→C++ shim
    ├── c++/HybridCounterSpecSwift.{hpp,cpp}      ← C++→Swift shim
    ├── NitroCounter-Swift-Cxx-Bridge.{cpp,hpp}   ← interop bridge for the module
    ├── NitroCounter-Swift-Cxx-Umbrella.hpp
    ├── NitroCounter+autolinking.rb               ← CocoaPods autolinking
    ├── NitroCounterAutolinking.swift             ← Swift-side factory
    └── NitroCounterAutolinking.mm                ← Obj-C++ registration
```

The piece authors care about is `ios/swift/HybridCounterSpec.swift`, which is
roughly:

```swift
public protocol HybridCounterSpec_protocol: HybridObject {
  func increment() throws -> Void
  func reset() throws -> Void
  func value() throws -> Int64
  func add(delta: Int64) throws -> Int64
}

open class HybridCounterSpec_base { public init() { /* … */ } }

public typealias HybridCounterSpec = HybridCounterSpec_protocol & HybridCounterSpec_base
```

Note nitrogen wraps every Swift method with `throws` regardless of the TS
interface — that's nitrogen's convention for surfacing errors across the
JS/Swift boundary.

## How the impl plugs in

`swift/HybridCounter.swift` is what the developer maintains:

```swift
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
```

Two things are doing work here:

1. **`HybridCounter: HybridCounterSpec`.** The class name has to be
   `HybridCounter` — `nitro.json` declares `implementationClassName:
   "HybridCounter"`, and `NitroCounterAutolinking.swift` (generated) literally
   calls `HybridCounter()` to register the factory. The autolinking code
   won't find anything else.

2. **`#if canImport(NitroModules)`.** Lets the file parse in any toolchain
   (stage ① is SwiftSyntax-only — never typechecks), and only flips the impl
   on once `NitroModules` and the generated `HybridCounterSpec` are in
   scope. SwiftSyntax walks the inactive branch either way, so stage ①
   sees the class regardless.

The Swift `: HybridCounterSpec` inheritance is the steady-state shape — by
design, not a gap. The other SwiftStitch packages address adjacent concerns
(the Swift × Android bridge in `nitrogen-swift-embedded`, the in-process
`.nitro.ts`-free path in `nitrogen-swift-spec-input`, the macro that emits
the C-bridge as peer decls in `nitrogen-swift-runtime`) — none of them
remove the iOS `: HybridCounterSpec` requirement.

## Type scope

Stage ① accepts: `Bool`, `Double`, `Float`, `Int64`, `UInt64`, `Void`. Strings,
arrays, optionals, structs, enums, generics raise diagnostics — see fixtures
under `packages/nitrogen-swift-input/Tests/.../Fixtures/`.

## Why iOS-only here

The `Hybrid<Name>.swift` source can declare any platforms at parse time —
the CLI takes `--ios <lang>` and `--android <lang>` independently. This
example uses `--ios swift` only because stock nitrogen rejects
`android: 'swift'` today (`Language swift is not a valid language for
android!`). Bringing first-class Swift to Android is what the rest of the
SwiftStitch packages (`-spec-input` alongside-pass + `-embedded`) are
designed to plug — see the root README's package table.

## CLI flags

`run.sh` uses the zero-flag form: inputs glob `swift/Hybrid*.swift`, both
outputs land in `specs/`, and per-spec platforms come from `nitro.json`
autolinking. The flags below override those defaults:

| Flag | Effect |
|---|---|
| `--input <path>` | Source `Hybrid<Name>.swift`. Repeatable. Default: glob `swift/Hybrid*.swift`. |
| `--out <dir>` | Write `<SpecName>.nitro.ts` per input file. Naming this (or `--out-json`) alone opts into a TS-only (or JSON-only) run. |
| `--out-json <dir>` | Write `<SpecName>.ir.json` per input file. |
| `--ios <lang>` | `swift` \| `kotlin` \| `cpp`. Flags override `nitro.json` wholesale. |
| `--android <lang>` | Same set. At least one platform must resolve, from flags or `nitro.json`. |

There's also `nitrogen-swift-input init <Name>`, which scaffolds
`swift/Hybrid<Name>.swift` and chains into a first emit — see
[`packages/nitrogen-swift-input/`](../../packages/nitrogen-swift-input/).
