# nitrogen-swift-input — RUNBOOK

Maintainer / integrator reference: exact CLI semantics, architecture, the IR
JSON contract, how to extend the type scope, and the test surface.
[`README.md`](README.md) is the author-facing companion (what to write, what
you get); this file is the "how it actually works" layer underneath it.
Verified against the source at 53/53 tests green.

## Where it sits in the pipeline

```
you author (scaffolded by init)     this package                       stock nitrogen
─────────────────────────────────────────────────────────────────────────────────────────
swift/Hybrid<Name>.swift  ──emit──▶ specs/<Name>.nitro.ts  ──bun nitrogen──▶ nitrogen/generated/
                            └─────▶ specs/<Name>.ir.json                     {shared,ios,android}/…
                                    (schema v1 — reserved for
                                     nitrogen-swift-spec-input,
                                     the no-.nitro.ts path)
```

- **Author-side only.** Consumers of a published module never install or run
  this CLI — generated outputs ship with the module package (`bun add` +
  `pod install` is the whole consumer story).
- **Couples only to nitrogen's CLI surface** (the `.nitro.ts` file format and
  `bun nitrogen`), not to nitrogen internals — the stable end of nitro's
  drift surface: the spec format and CLI move far more slowly across nitro
  releases than nitrogen's internals or generated-output shapes.

## The authoring loop

What an author actually does, end to end. `Hybrid<Name>.swift` is **not
hand-created from scratch** — step ① scaffolds it:

```
① nitrogen-swift-input init Counter
     → writes swift/HybridCounter.swift            (starter: #if canImport wrap,
                                                    : HybridCounterSpec, no methods yet)
     → chains a first emit: specs/Counter.nitro.ts + specs/Counter.ir.json

② add the spec to nitro.json                       (init does NOT do this — § Known gaps)
     "autolinking": { "Counter": { "ios": { "language": "swift",
                                            "implementationClassName": "HybridCounter" } } }
     (alongside the usual nitro.json module fields — cxxNamespace, iosModuleName, …)

③ edit swift/HybridCounter.swift — add public methods
     the same file is the iOS implementation you ship

④ nitrogen-swift-input emit                        (zero-flag; re-run after every spec edit)

⑤ bun nitrogen specs && pod install                (stock nitro from here on)
```

The file ① scaffolds, trimmed (full listing with its explanatory docstring:
README § "Scaffolding a new HybridObject"; a filled-in real one:
`example/counter-module/swift/HybridCounter.swift`):

```swift
#if canImport(NitroModules)
import NitroModules

public final class HybridCounter: HybridCounterSpec {
    public override init() { super.init() }
    // add public methods here — they become the spec surface
}
#endif
```

Consumers of the published module repeat none of this — the generated
outputs ship with the package.

## Design invariants

These four decisions explain most of the code's shape:

1. **Convention over annotation.** A HybridObject is any class whose name
   starts with `Hybrid` plus at least one more character. No attribute, no
   macro, no marker protocol — so the user's project compiles whether or not
   this tool ever runs, on any Swift toolchain.
2. **Parse, never typecheck.** The extractor is SwiftSyntax-only. Nothing is
   resolved: types are matched by *spelling* (`Int64` the token, not
   `Swift.Int64` the type). This is also why `#if canImport(NitroModules)`
   works: the visitor walks with `viewMode: .sourceAccurate`, which visits
   *inactive* `#if` regions too. One file can therefore be both the spec
   source (parsed before NitroModules exists) and the shipping implementation
   (compiled after `bun nitrogen` + `pod install`). Pinned by the
   `InitTemplateTests` round-trip test.
3. **Platforms come from outside the source.** Swift code never declares
   `{ ios, android }` bindings; they come from CLI flags or `nitro.json`.
   Keeps this front-end symmetric with the BridgeJS front-end and avoids a
   fictional attribute the compiler would reject.
4. **Fail loud on what it can't model.** Unsupported *types* throw a typed
   `Diagnostic` carrying `file:line:col`. (Unsupported *member kinds* are
   currently ignored silently — a known gap, see § Known gaps.)

## CLI reference — exact semantics

Two subcommands. Bare invocation prints usage to stderr and exits `64`.

### Exit codes (sysexits convention)

| Code | Meaning |
|---|---|
| `0` | Success — including "input had no `Hybrid*` class" (warning to stderr, see below). |
| `64` | No subcommand given (usage printed). |
| `65` | Any `CLIError` — bad flags, unreadable input, parse diagnostic, unwritable output, malformed `nitro.json`, unresolvable platforms. |
| `70` | Unexpected (non-`CLIError`) error. |

### `emit` resolution order

`emit [--input <file>]… [--out <dir>] [--out-json <dir>] [--ios <lang>] [--android <lang>]`

| What | Resolution | Failure mode |
|---|---|---|
| Inputs | `--input` (repeatable, exact paths), else glob `<dir>/Hybrid*.swift` relative to CWD (non-recursive, sorted), where `<dir>` is `swiftstitch.userSwiftDir` from `nitro.json` if that block is present, otherwise `swift/`. | Empty set → error naming the directory actually scanned. |
| Outputs | Neither flag → **both** artifacts to `specs/`. Exactly one flag → **only** that artifact (TS-only / JSON-only opt-in). Both flags → both, to their dirs. | Write failure → error. Output dirs are created as needed. |
| Platforms (per spec) | CLI flags win **wholesale** if any are present (no per-platform mixing with `nitro.json`). Else `nitro.json` `autolinking.<SpecName>.{ios,android}.language`. | Empty after resolution → error `no platforms for spec`. |
| `nitro.json` | Loaded once from `./nitro.json` (CWD-relative — per-package scripts `cd` first). Missing file is fine (→ flags-only). | Malformed file is a **hard error**, never a silent fallback. |

Language values: `--ios`/`--android` accept `swift`, `kotlin`, `cpp`, or
`c++`. In `nitro.json` the value must be nitro's own spelling — `"c++"`, not
`"cpp"` (`"cpp"` there is treated as an unknown language and skipped; an
entry whose languages are all unknown resolves to empty platforms and errors).

Behavioral details:

- **All-or-nothing.** All inputs are parsed and platform-resolved before
  anything is written. A `Diagnostic` in any file aborts the whole run with
  nothing on disk; only the *first* diagnostic is reported.
- **One output file per input file, named after the first spec.** A file
  declaring `HybridA` and `HybridB` produces a single `A.nitro.ts` (and
  `A.ir.json`) containing *both* interfaces. Prefer one class per file.
- **No-class inputs warn, don't fail.** `warning: no `Hybrid<Name>` class in
  <file>` on stderr, exit stays `0`. (Emitted once per file, whichever output
  loop reaches it first.)
- `.ir.json` is written atomically, then a trailing `\n` is appended
  (POSIX text-file convention); `.nitro.ts` gets its newline from the
  emitter.

### `init` semantics

`init <Name> [--out <dir>] [--ios <lang>] [--android <lang>] [--force]`

1. **Normalize the name** (`InitTemplate.normalize`): trim whitespace; strip
   a `Hybrid` prefix if present (`HybridCounter` → `Counter`); reject bare
   `Hybrid`, empty, leading digits, non-identifier characters.
2. **Refuse to overwrite** `<out>/Hybrid<Name>.swift` unless `--force`
   (default out dir: `swift/`).
3. **Write the template** — the `#if canImport(NitroModules)` +
   `: Hybrid<Name>Spec` starter with the spec/impl-duality docstring, no
   public methods yet.
4. **Chain into `emit`** with `--input` pinned to the new file and platforms
   from `init`'s own `--ios`/`--android` (default `ios: swift,
   android: kotlin`). Because these flags are always non-empty, the chained
   emit **never consults `nitro.json`** — deliberate, since at init time the
   spec usually isn't in `autolinking` yet.
5. Print `next: bun nitrogen specs && pod install`.

Gap worth knowing: `init` neither creates nor patches `nitro.json`. On a bare
directory the printed next step fails until you write `nitro.json` (with the
`autolinking.<Name>` entry) yourself — and zero-flag `emit` re-runs need that
entry too. See § Known gaps.

### Common errors

| Message | Cause |
|---|---|
| `error: '<name>' is not a valid spec name (expected a Swift identifier like `Counter`)` | `init` got a non-identifier, or just `Hybrid`. |
| `error: <path> already exists (pass --force to overwrite)` | `init` refuses to clobber an existing Swift file. |
| ``error: no `Hybrid*.swift` files in <dir> (pass --input <path> if your sources live elsewhere)`` | Default glob found nothing. `<dir>` is `swiftstitch.userSwiftDir` when nitro.json declares one, else `swift/`. |
| ``error: no platforms for spec `X` — pass --ios <lang> / --android <lang> or add `autolinking.X` to nitro.json`` | Spec resolved to zero platform bindings. |
| `error: <path> is not valid nitro.json: …` | `nitro.json` exists but doesn't decode — fixed, never silently ignored. |
| `error: --ios: unsupported language `x` (expected swift / kotlin / cpp)` | Bad `--ios`/`--android` value. |
| `error: <file>:<line>:<col>: error: Type `String` not supported …` | Out-of-scope type at that source location (see § Type scope). |
| ``warning: no `Hybrid<Name>` class in <file>`` | Parser found no `Hybrid*` class — stderr only, exit stays `0`. |

## Architecture

Two targets — everything testable lives in the library:

| Target | Role |
|---|---|
| `NitrogenSwiftInputCore` | Library: parse, model, emit, decode. No `exit()`, no `print` — throws typed errors. |
| `NitrogenSwiftInputCLI` | One `main.swift`: argv parsing, defaults/globbing, file I/O, stderr/exit codes, subcommand dispatch. |

### File map (Core)

| File | Responsibility |
|---|---|
| `IR.swift` | The data model: `HybridObjectIR` (`className`, derived `specName` = name minus `Hybrid`, `platforms`, `methods`, optional `sourceLocation`), `MethodIR` (+`isThrowing`), `ParameterIR`, `TypeIR` (6 cases), `PlatformBinding`, `Diagnostic` (an `Error` with optional `file:line:col`). |
| `HybridObjectExtractor.swift` | `SyntaxVisitor` over the parsed tree. Matches `ClassDeclSyntax` by name prefix, delegates members to `MethodExtractor`, stamps caller-supplied platforms, records the first diagnostic. Recurses into children — nested `Hybrid*` classes are picked up wherever they appear. |
| `MethodExtractor.swift` | Member filtering (only `FunctionDeclSyntax` with a `public` modifier) and signature mapping: parameter labels (external label; `_` → internal name), return type (missing clause / `()` / `Void` → `.void`), `throws` detection, and the **type gate** (`parseType`) that maps or rejects every type spelling. |
| `NitroTSEmitter.swift` | IR → `.nitro.ts` text. Import line collects only what's used (`HybridObject` always; `Int64`/`UInt64` when referenced). Platform spec rendered in canonical order (`ios` then `android`) with `;` separators. `Float` folds to TS `number`. |
| `IRJSONCodec.swift` | IR ↔ JSON (schema v1). Pretty-printed, sorted keys. Decode is strict: wrong `schemaVersion`, unknown platform/language/type-kind strings are errors. Source locations are **not** serialized. |
| `NitroJSONReader.swift` | Loads `nitro.json`; missing → `nil`, malformed → typed error. `platforms(for:in:)` maps `autolinking.<Spec>.{ios,android}.language`; unknown language strings are skipped (forward-compat with languages other tools may add). |
| `InitTemplate.swift` | Pure string rendering + name normalization for `init`. CLI owns the disk I/O. |
| `SmokeParse.swift` | Historical Phase-1A.1 smoke API proving swift-syntax is wired; kept because its tests double as a parser sanity check. |

### `executeEmit` data flow (main.swift)

```
argv ─▶ EmitOptions ─▶ ①resolve inputs ─▶ ②resolve output dirs ─▶ ③load nitro.json
      ─▶ ④parse every file (platforms: []) ─▶ ⑤re-stamp per-spec platforms (error if empty)
      ─▶ ⑥write .nitro.ts / .ir.json per input file
```

The extractor deliberately accepts an empty `platforms` list (④) — the CLI
re-builds each IR with resolved bindings (⑤) before anything is emitted,
where empty is enforced as an error. That's why `HybridObjectIR.platforms`
looks writable-by-reconstruction rather than mutable.

## Type scope and mapping

| Swift spelling | `TypeIR` | TS | IR JSON `kind` | Note |
|---|---|---|---|---|
| `Bool` | `.bool` | `boolean` | `bool` | |
| `Double` | `.double` | `number` | `double` | |
| `Float` | `.float` | `number` | `float` | IR keeps the distinction; TS folds to `number` (nitrogen's NumberType = double). |
| `Int64` | `.int64` | `Int64` | `int64` | TS type imported from `react-native-nitro-modules`. |
| `UInt64` | `.uint64` | `UInt64` | `uint64` | Same. |
| `Void` / `()` / no clause | `.void` | `void` | `void` | |

Everything else is **rejected with a `Diagnostic`** at the use site:
`Int`/`Int8`/`Int16`/`Int32`/`UInt…` (named explicitly — scope is fixed-width
64-bit only), `String`, `Optional`/`T?`, `Array`/`[T]`, and any other
spelling — which covers user structs/enums, closures, generics, tuples.

`throws` is captured as `MethodIR.isThrowing` (IR only — the TS surface
never shows it; nitrogen wraps every generated Swift method in `throws`
regardless).

### Member kinds — what's extracted vs ignored

| Member | Behavior today |
|---|---|
| `public func` | Extracted. |
| `internal`/`private`/default-access `func` | Skipped (by design). |
| `init` | Skipped (by design — the spec has no constructor surface). |
| `public var` / `let` | **Silently ignored** — no property support, no diagnostic. Nitro specs do support properties; see § Known gaps. |
| `public static func` / `class func` | **Extracted as if instance methods** — wrong-shaped output; see § Known gaps. |
| `async` functions | **`async` is not detected** — extracted as synchronous; see § Known gaps. |

## The IR JSON contract (schema v1)

Written as `<FirstSpecName>.ir.json`; the downstream consumer is
`nitrogen-swift-spec-input` (migrating). Full shape:

```jsonc
{
  "schemaVersion": 1,          // decoder rejects any other value
  "objects": [{
    "className": "HybridMath", // Swift impl class
    "specName": "Math",        // className minus "Hybrid" (serialized redundantly)
    "platforms": [             // resolved bindings, post-nitro.json/flags
      { "platform": "ios", "language": "swift" }     // language: swift | kotlin | c++
    ],
    "methods": [{
      "name": "add",
      "isThrowing": true,      // the fact the TS format throws away
      "parameters": [ { "label": "a", "type": { "kind": "double" } } ],
      "returnType": { "kind": "double" }
      // kind: bool | double | float | int64 | uint64 | void
    }]
  }]
}
```

Contract rules:

- **Source locations are not part of the wire format.** They exist on the
  in-memory IR for diagnostics only; `decode(encode(x))` returns IRs with
  `sourceLocation == nil`.
- Encoding is deterministic (`.sortedKeys`) — safe to golden-test and diff.
- **Evolution:** incompatible changes bump `schemaVersion`; decoders must
  keep rejecting versions they don't know (a stale TS adapter must not
  silently misread newer output). Additive type kinds are *also* breaking for
  old decoders (unknown `kind` throws) — treat any kind addition as a
  coordinated bump with `nitrogen-swift-spec-input` once that package lands.

## Extending the type scope — recipe

For a new *primitive* mapping (say `String`), touch, in order:

1. `IR.swift` — add the `TypeIR` case (+ `swiftSpelling`).
2. `MethodExtractor.parseType` — map the spelling (and remove it from the
   explicit rejection list if present).
3. `NitroTSEmitter.tsType` — the TS spelling; `collectSymbols` too if it
   needs an import from `react-native-nitro-modules`.
4. `IRJSONCodec` — `TypeJSON.init(from:)` and `toIR()` (both directions);
   consider the schema-version note above.
5. Tests — add a `ParamCase`/`ReturnCase` row in `TypesCoverageTests`, extend
   `Fixtures/HybridTypes.swift`, and update **both goldens**
   (`HybridTypes.nitro.ts.golden`; `HybridMath.*` only if you touched that
   fixture). Goldens are hand-maintained — regenerate by running the emitter
   and pasting, then eyeball the diff.
6. `README.md` type-scope table (and the root README if the scope statement
   there changes).

Structured types (`T?`, `[T]`, `Promise<T>`) additionally need: `parseType`
handling of the syntax node (`OptionalTypeSyntax`, `ArrayTypeSyntax`,
generic-argument walking), an associated-value `TypeIR` case, and a nested
JSON shape — that's the schema-v2 conversation, not a mechanical edit.

## Test surface

`swift test --package-path packages/nitrogen-swift-input` — **53 tests /
9 suites**, ~1–2 s. Swift Testing (`@Suite`/`@Test`), fixtures copied as
bundle resources.

| Suite | File | Pins |
|---|---|---|
| swift-syntax smoke parse | `SmokeParseTests` | Dependency wiring; parser accepts/flags sources. |
| HybridObject class extraction | `HybridObjectExtractorTests` | Prefix convention (bare `Hybrid` excluded), multi-class files, empty-platform pass-through, stray `@HybridObject` attribute tolerated, source locations. |
| Method signature extraction | `MethodExtractorTests` | public-only filtering, label rules (`_` → internal name), per-type accept/reject diagnostics. |
| Type coverage | `TypesCoverageTests` | Full 6-type matrix as params and returns (parameterized), void variants, throws-drops-from-TS, import minimality, `HybridTypes` golden byte-for-byte. |
| .nitro.ts emitter | `NitroTSEmitterTests` | `HybridMath` extractor→emitter golden. |
| IR JSON codec | `IRJSONCodecTests` | Encode/decode round-trip, `HybridMath` IR golden, strict version/kind rejection. |
| nitro.json reader | `NitroJSONReaderTests` | missing-nil / malformed-throws, per-platform lookup, unknown-language skip. |
| Init template | `InitTemplateTests` | Name normalization matrix, template substitution, and the template→extractor round-trip (proves `#if canImport` parsing). |
| End-to-end | `EndToEndTests` | Real subprocess run: built CLI binary → `.nitro.ts` → real `bun nitrogen` → asserts the 6 generated bridge artifacts + spot-checks the C++ header. |

E2E prerequisites (it `#require`s both, with clear messages): `swift build`
has produced `.build/debug/nitrogen-swift-input`, and `bun install` at the
repo root has populated `node_modules/.bin/nitrogen`. Temp module dirs go
under `.build/e2e/<uuid>` so Node module resolution walks up to the
workspace root; cleaned up per-run.

Fixtures: `HybridMath.swift` (+ `.nitro.ts.golden`, `.ir.json.golden`),
`HybridTypes.swift` (+ `.nitro.ts.golden`), `HybridSimpleMath.swift` (e2e).

## Known gaps

Ranked by how much they'd surprise an author. The first three are the
"silent wrongness" class — the tool should reject what it can't model:

1. **Public properties are dropped without a diagnostic.** Nitro specs
   support properties, so `public var count: Int64` looks like it should
   work; today it just vanishes from the spec. Minimum fix: diagnostic.
   Real fix: extract properties into the IR/TS.
2. **`static`/`class` funcs are emitted as instance methods.** The generated
   spec then demands an instance method the impl doesn't have — a confusing
   conformance error far from the cause. Fix: skip with a diagnostic.
3. **`async` is invisible.** An `async` method is emitted as sync (nitro
   would model it as `Promise<T>`). Fix: reject with a diagnostic until
   Promise support exists.
4. **`init` doesn't scaffold `nitro.json`** — the printed
   `next: bun nitrogen …` step fails on a bare directory, and later
   zero-flag `emit` runs need the `autolinking` entry by hand.
5. **Type scope is the adoption ceiling.** `String` is the first thing a new
   author will type. Post-v0.1.0, expanding scope (String → Optional/Array →
   Promise) is the highest-leverage DX work; the recipe above makes each
   primitive mechanical.
6. **First-diagnostic-only reporting** — one error per run means one fix per
   iteration. Collecting all diagnostics before aborting would tighten the
   loop.
7. **No `implementationClassName` cross-check.** If `nitro.json` says
   `HybridCounter` but the class is `HybridCount`, nothing warns until the
   generated autolinking factory fails to compile.
8. **Multi-class output naming** — all specs from one file land in a single
   `<FirstSpec>.nitro.ts` / `.ir.json`. Documented; per-spec files would be
   less surprising if multi-class files ever become common.
