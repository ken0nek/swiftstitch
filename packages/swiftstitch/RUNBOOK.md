# `swiftstitch` — runbook

## What you actually do

In a nitro module — the directory holding `nitro.json` — one command
replaces the usual `nitrogen-swift-input emit && bunx nitrogen` sequence, and
chains straight into the Android alongside pass too:

```bash
cd <module-dir>   # wherever your nitro.json lives, e.g. example/math-module
NITRO_SWIFTC=~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swiftc \
bun ../../packages/swiftstitch/src/cli.ts build \
  --input-bin    ../../packages/nitrogen-swift-input/.build/release/nitrogen-swift-input \
  --embedded-bin ../../packages/nitrogen-swift-embedded/.build/release/nitrogen-swift-embedded
```

(v0.2 doesn't publish `swiftstitch` or either Swift binary yet, so today
that's `bun <path-to-cli.ts>` with explicit `--input-bin`/`--embedded-bin`
paths into each package's `.build/release/`, as above. Once `swiftstitch` is
an installed dependency, the same thing is just `swiftstitch build`.)

Add the [one `include` line](#the-cmake-include-line) to your
`android/CMakeLists.txt` once, and `./gradlew assembleDebug` compiles your
Swift into the host `.so`. `NITRO_SWIFTC` only matters for a module with a
[`swiftstitch` block](#the-swiftstitch-block-in-nitrojson) — an iOS-only
module never touches it.

**What it does.** `swiftstitch build` runs, in order, from the module
directory:

| # | Step | Command | Runs when |
|---|---|---|---|
| 1 | `input-emit` | `<input-bin> emit` | `swiftstitch.userSwiftDir` exists and contains `Hybrid*.swift` |
| 2 | `nitrogen` | `bunx nitrogen` | always |
| 3 | `alongside` | `<embedded-bin> alongside --nitro-json nitro.json` | always — no-ops on its own with no `swiftstitch` block |

No `swiftstitch.userSwiftDir` (or no `swiftstitch` block at all) means step 1
is skipped, not an error — that's the hand-authored-`.nitro.ts` case. It
fails fast on the first non-zero exit and prints that step's stderr. A
missing `--input-bin`/`--embedded-bin` binary that also isn't on `PATH`
fails with a message naming it, rather than a bare `ENOENT`.

## CLI

```
swiftstitch build [--module-dir <dir>] [--input-bin <path>] [--embedded-bin <path>]
```

One command — no `doctor`, no subcommand tree. `--module-dir` defaults to
the current directory. `--input-bin`/`--embedded-bin` default to the bare
names `nitrogen-swift-input`/`nitrogen-swift-embedded`, resolved on `PATH`.

## The `swiftstitch` block in `nitro.json`

Opt-in is explicit. Nitrogen strips unknown top-level keys at parse, so this
is invisible to it:

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

Both keys are required when the block is present, and `android.language`
must be `"c++"` — that's what nitrogen accepts; `alongside` supplies the
concrete class underneath it, generated from your Swift. No block at all
means an iOS-only module: `swiftstitch build` still runs `input-emit` (that
part is gated on `Hybrid*.swift` existing, not on this block), and
`alongside` just has nothing to do and exits 0 having written nothing.

`swiftstitch build` itself only reads `userSwiftDir` off this block, to
decide whether to run `input-emit`. `swiftOnAndroid`, `implementationClassName`,
and the `android.language == "c++"` requirement are read and enforced by
`alongside`, not by this package — see
[`../nitrogen-swift-embedded/RUNBOOK.md`](../nitrogen-swift-embedded/RUNBOOK.md#the-swiftstitch-block)
for that validation and the three files it writes.

## The CMake include line

The fragment `alongside` writes ends in
`target_sources(<androidCxxLibName> PRIVATE ...)`, which runs at include
time, so **`add_library` must already have run**. Add it after your existing
autolinking include, in this order:

```cmake
add_library(${PACKAGE_NAME} SHARED src/main/cpp/cpp-adapter.cpp)

include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/EmbeddedTest+autolinking.cmake)
include(${CMAKE_SOURCE_DIR}/../swiftstitch/generated/EmbeddedTest+swift-embedded.cmake)
```

(`EmbeddedTest` stands in for whatever `androidCxxLibName` your module
declares.) This is a one-time setup step in a file `swiftstitch build`
doesn't touch. Note the two paths differ past `../`: `alongside` writes into
`swiftstitch/generated/`, deliberately outside the `nitrogen/generated/` tree
that nitrogen sweeps clean on every run.

## `NITRO_SWIFTC`

The CMake fragment reads this environment variable at configure time and
hard-fails without it:

```bash
export NITRO_SWIFTC=~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swiftc
```

It stays an env var rather than a `nitro.json` value because the toolchain
path is per-machine. It's only read at Gradle build time, by a module with a
`swiftstitch` block — `swiftstitch build` itself never touches it.

## Writing a spec by hand

There is no `SwiftHybridObject<T>` convenience type in this version.
Nitrogen resolves the type argument to `HybridObject<...>` syntactically
(walking the literal object-type syntax with `ts-morph`) rather than through
the type checker, so a type alias standing in for that argument is invisible
to it — confirmed by spiking a minimal alias against nitrogen 0.36.1 (and
again against 0.37.1, with the same result), which
failed to resolve the language even on a plain indexed access before ever
reaching a conditional type. **That is a current nitrogen limitation, not a
SwiftStitch design choice**; if a future nitrogen resolves aliases, this
package can add the shorthand back.

In practice this only affects a `.nitro.ts` you write by hand. Write the
Android platform directly as `'c++'`:

```ts
import type { HybridObject } from 'react-native-nitro-modules'

export interface SimpleMath extends HybridObject<{ ios: 'swift', android: 'c++' }> {
  // ...
}
```

If instead you're authoring `Hybrid<Name>.swift` and letting `swiftstitch
build`'s `input-emit` step generate the `.nitro.ts` for you, this never comes
up: the emitted spec already writes `android: 'c++'` literally, because
that's what `autolinking.<Spec>.android.language` says in `nitro.json` (and
`alongside` requires it to say exactly that). The alias was only ever a
spelling convenience for the hand-authored path.

## Tests

```bash
cd packages/swiftstitch && bun test   # 3/3 expected
bunx tsc --noEmit                     # clean
```

Only `planSteps` has automated coverage — it's pure, which is the point of
keeping it separate. `runBuild` and `cli.ts` (subprocess orchestration, PATH
resolution, file I/O) were exercised by hand against a scratch module for
this task; they get their first real exercise in CI once Task 4's example
module runs `swiftstitch build` for real.

## Known gaps

- **`userSwiftDir` may be any directory** — this used to be a gap and is not
  one any more. `swiftstitch build` decides whether to run `input-emit` by
  globbing `swiftstitch.userSwiftDir`, and `nitrogen-swift-input emit` now
  reads the same key to pick the directory it scans, so the two cannot
  disagree. Previously `emit` scanned a hardcoded `swift/` regardless, and a
  module pointing `userSwiftDir` elsewhere would see `swiftstitch build`
  correctly decide to run `input-emit` and then watch it fail with
  `` no `Hybrid*.swift` files in swift/ ``. An explicit `--input` still wins
  over both.

## See also

- [`../nitrogen-swift-embedded/RUNBOOK.md`](../nitrogen-swift-embedded/RUNBOOK.md) —
  the `alongside` pass this CLI's third step drives: the three emitted files,
  the full error table, and the `try!`-error-propagation limitation.
- [`../nitrogen-swift-input/RUNBOOK.md`](../nitrogen-swift-input/RUNBOOK.md) —
  the `emit` step's exact CLI semantics.
