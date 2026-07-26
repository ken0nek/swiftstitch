# Example: nitrogen-swift-spec-input *(stub)*

🚧 **Not yet runnable.** This directory will hold a runnable walkthrough
once `packages/nitrogen-swift-spec-input/` lands.

## What this example will demonstrate

The "dream path" — feed IR JSON straight into nitrogen, with no
`.nitro.ts` artifact on disk. Pairs with whichever front-end produced
the IR (`nitrogen-swift-input` here, but `-bridgejs` works too once it
grows IR-JSON output).

This package is a **library, not a CLI** — the example is a small Bun
script.

## Pipeline shape

```
swift/HybridCounter.swift
   │  nitrogen-swift-input emit --out-json specs --ios swift
   ▼
specs/Counter.ir.json                     ← only IR; no .nitro.ts
   │  bun run drive.ts (uses runFromIRFiles)
   ▼
nitrogen/generated/{shared,ios}/...
```

`drive.ts` (illustrative — the final API may differ):

```ts
import { runFromIRFiles } from 'nitrogen-swift-spec-input'

await runFromIRFiles(['./specs/Counter.ir.json'], {
  outputDirectory: './nitrogen/generated',
})
```

| | |
|---|---|
| **Prepare** | One or more `<Name>.ir.json` files produced by `nitrogen-swift-input` (or any upstream that writes the schema-v1 IR). |
| **Generates** | `nitrogen/generated/{shared,ios,android}/...` directly — same tree `bun nitrogen` would have produced. |
| **Min toolchain** | Bun 1.x. |
| **Runtime story** | Lives in [`../rn-app/`](../rn-app/) once that lands. |

## Why a separate example from `nitrogen-swift-input`

Same Swift source, same generated tree at the end — but no `.nitro.ts`
artifact in between. The byte-for-byte equivalence test upstream pins that
the dream path is genuinely interchangeable with the `bun nitrogen` path.
This example is the smallest demo of that equivalence.

This package also hosts the **alongside-pass driver** that makes Swift × Android
work without nitrogen schema changes — see
[`../nitrogen-swift-embedded/`](../nitrogen-swift-embedded/) for the
end-to-end Android story.

## See also

- [`packages/nitrogen-swift-spec-input/`](../../packages/) *(not yet present)*
- [`../nitrogen-swift-input/`](../nitrogen-swift-input/) — the front-end that produces the IR JSON consumed here.
