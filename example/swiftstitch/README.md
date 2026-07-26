# Example: swiftstitch *(stub)*

🚧 **Planned (net-new package).** This directory will hold the user-facing
one-command walkthrough once `packages/swiftstitch/` lands.

## What this example will demonstrate

The headline DX: write `Hybrid<Name>.swift`, run **one** command, get a
ready-to-build RN module on iOS and Android.

```sh
bunx swiftstitch nitro
```

Under the hood that runs `bun nitrogen` and the alongside-pass
(`-spec-input` driver) in sequence — replacing the C++ Android stub with
Swift glue, emitting the CMake recipe that drives `swiftc` at native build
time.

## Pipeline shape

```
swift/HybridCounter.swift  +  nitro.json
   │  bunx swiftstitch nitro
   │  ├─ nitrogen-swift-input emit       (Swift → spec)
   │  ├─ bun nitrogen                    (spec → C++/Swift bridge)
   │  └─ runAlongsidePass                (C++ Android stub → Swift glue)
   ▼
nitrogen/generated/{shared,ios,android}/...
```

| | |
|---|---|
| **Prepare** | A standard nitro project — `nitro.json` + `Hybrid<Name>.swift` source(s). |
| **Generates** | `nitrogen/generated/` with the iOS Swift bridge **and** the Android Swift glue + CMake recipe. |
| **Min toolchain** | Bun 1.x, TypeScript 5. (Native build adds Swift 6.3.1 + NDK r27+ if Android Swift is enabled.) |
| **Runtime story** | Lives in [`../rn-app/`](../rn-app/) once that lands. |

## How `SwiftHybridObject` works

The user writes:

```ts
import type { SwiftHybridObject } from 'swiftstitch'

export interface Counter extends SwiftHybridObject<{
  ios: 'swift';
  android: 'swift';
}> {
  // …
}
```

`SwiftHybridObject` resolves to `HybridObject<{ ios: 'swift'; android: 'c++' }>`
underneath — keeping nitrogen's schema unchanged. The Android Swift story
is wired up by the alongside-pass *after* `bun nitrogen` runs, so no schema
patch and no nitrogen fork.

## See also

- [`packages/swiftstitch/`](../../packages/) *(not yet present — net-new)*
- [`../nitrogen-swift-spec-input/`](../nitrogen-swift-spec-input/) — hosts the alongside-pass driver this CLI invokes.
