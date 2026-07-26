# Example: nitrogen-swift-bridgejs *(stub)*

🚧 **Not yet runnable.** This directory will hold a runnable codegen
walkthrough once `packages/nitrogen-swift-bridgejs/` lands.

## What this example will demonstrate

The Bun-only path from a JavaScriptKit BridgeJS skeleton document to a
nitrogen-compatible `.nitro.ts` spec — same downstream nitrogen flow as
[`../nitrogen-swift-input/`](../nitrogen-swift-input/), different front-end.

## Pipeline shape

```
build/bridgejs/Math.bridgejs.json        ← BridgeJS prepass output (you provide)
   │  bunx nitrogen-swift-bridgejs --input ... --out src/specs --ios swift
   ▼
src/specs/Math.nitro.ts
   │  bun nitrogen
   ▼
nitrogen/generated/{shared,ios}/...
```

| | |
|---|---|
| **Prepare** | A `*.bridgejs.json` produced by JavaScriptKit's BridgeJS pass — typically already part of your SwiftStitch build. |
| **Generates** | `<Name>.nitro.ts` (and optionally combined IR JSON, if/when the adapter grows IR-JSON output). |
| **Min toolchain** | Bun 1.x. No Swift on the codegen host. |
| **Runtime story** | Lives in [`../rn-app/`](../rn-app/) once that lands. |

## Why a separate example from `nitrogen-swift-input`

The cross-adapter equivalence tests upstream pin that `-bridgejs` and
`-input` produce byte-identical `.nitro.ts` from the same `HybridMath`
fixture — but the *prepare* step differs (a BridgeJS prepass vs. authoring
plain Swift), and that's the reason to pick one over the other. This
example demos the BridgeJS-first path; pick `-input` when you don't already
run BridgeJS.

## See also

- [`packages/nitrogen-swift-bridgejs/`](../../packages/) *(not yet present)*
- [`../nitrogen-swift-input/`](../nitrogen-swift-input/) — the plain-Swift
  front-end, if you don't already run BridgeJS.
