# nitrogen-swift-embedded

SwiftPM CLI. Reads IR JSON, emits the Swift↔C++ glue for Android, and drives
`swiftc` in Embedded mode to produce a `.o` with **no Swift runtime**.

This README is the executive summary. Exact CLI semantics, the emitted file
shapes, the error catalog, and the test map live in [`RUNBOOK.md`](RUNBOOK.md).

## When to use this

You want the same Swift implementation that ships on iOS to run on Android,
**without a Swift stdlib in the APK** — no `libswiftCore.so` in `jniLibs/`,
no Foundation overlay, no per-Hybrid `.so`.

The IR JSON comes from
[`nitrogen-swift-input`](../nitrogen-swift-input/) (or, later,
`nitrogen-swift-bridgejs`). Everything here is downstream of that.

Two things this package deliberately does **not** do:

- **It does not link.** `compile` stops at the `.o`; you link it into your
  host `.so` with NDK clang.
- **It does generate the Android CMake fragment.** See `CMakeFragmentEmitter`
  and the `alongside` subcommand below.

The `alongside` subcommand is the driver: run after `bunx nitrogen`, it writes
the `@c` bridge, the C++ glue header, and the CMake fragment into
`swiftstitch/generated/`, its own tree, sitting alongside `nitrogen/generated/`
rather than inside it, so nitrogen's cleanup never reaches them.
`swiftstitch build` chains the whole pipeline for you; you can also invoke this
CLI directly from your own build script.

## Toolchain

| | |
|---|---|
| Build this package | Swift **6.2+** (`swift-tools-version: 6.0`) |
| Run `compile` | Swift **6.3+** — `@c` and Embedded mode are 6.3-only |
| Link the `.o` | Android **NDK r27+** (not invoked by this CLI) |

Point `--swiftc` at an explicit 6.3.x toolchain. The test helpers probe exactly
two paths, `swift-6.3.1-RELEASE` then `swift-6.3.0-RELEASE`, under
`~/Library/Developer/Toolchains/`. `swift-latest.xctoolchain` is deliberately
not among them: it can resolve below 6.3 and would make the probe claim a
toolchain it does not have.

## Build

```sh
swift build --package-path packages/nitrogen-swift-embedded
# binary: packages/nitrogen-swift-embedded/.build/debug/nitrogen-swift-embedded
```

## The pipeline

```
① nitrogen-swift-input emit           # produces <Name>.ir.json
② nitrogen-swift-embedded emit        # → <Class>+CBridge.swift   (@c shims)
③ nitrogen-swift-embedded emit-cpp    # → <Class>.hpp             (C++ subclass)
④ nitrogen-swift-embedded compile     # → <Class>.o               (Embedded, no runtime)
⑤ NDK clang -shared ... <Class>.o     # you do this — not the CLI
```

Steps ②–④ each take `--ir <path>`; see [`RUNBOOK.md`](RUNBOOK.md) § CLI for
the full flag surface and a copy-pasteable worked example.

## What it generates

| Output | What it is |
|---|---|
| `<Class>+CBridge.swift` | `@c` functions giving each spec method a stable C-ABI symbol, with the user's Swift class round-tripped through an opaque `void*` handle via `Unmanaged`. |
| `<Class>.hpp` | Concrete C++ subclass of nitrogen's `<Class>Spec`, overriding each virtual method by forwarding to the `extern "C"` symbol. |
| `<Class>.o` | Embedded-mode object targeting `*-none-none-elf` — bare-metal ELF, no OS, no runtime. |

The `*-none-none-elf` choice is the whole trick: AAPCS64 matches what Android
expects, so the only undefined symbols left are bionic primitives (`free`,
`memmove`, `posix_memalign`, `__stack_chk_*`, `putchar`). The linked `.so`
carries only bionic + `libc++_shared` in `DT_NEEDED`.

## Symbol contract

For `HybridFoo` with `bar(a: Double) -> Int64`:

| Symbol | Type |
|---|---|
| `HybridFoo_create` | `void* ()` |
| `HybridFoo_destroy` | `void (void*)` |
| `HybridFoo_bar` | `int64_t (void*, double)` |

## Type scope

`Bool`, `Double`, `Float`, `Int64`, `UInt64`, `Void` — the same primitive
subset the input package accepts. `Float` widens to `double` in the C++
signature (matching nitrogen's `NumberType`), with a `static_cast` at the
`@c` boundary. Anything else is rejected with a diagnostic.

**Throwing methods are wrapped in `try!`** — a thrown error aborts rather than
propagating across the C ABI. That is a real iOS/Android parity gap; closing
it needs an out-param error channel and is a tracked follow-up.

## Architectures

`aarch64-none-none-elf`, `x86_64-unknown-none-elf`, `armv7-none-none-eabi`.
Only `aarch64` (Android `arm64-v8a`) is covered by a test, with compile, NDK link,
and `DT_NEEDED` assertions. The other two are emitted but unexercised, and
nothing here has yet run on a device or emulator; multi-ABI is out of scope for
now.

## Tests

```sh
swift test --package-path packages/nitrogen-swift-embedded
```

23 tests. Twenty are pure emitter/golden/CLI checks; two invoke a real Swift
6.3 `swiftc`; one runs the full pipeline through an NDK link and asserts
`DT_NEEDED` is bionic-only with the `@c` symbols exported.

**Those three skip, not fail, without a toolchain.** Their
conditions live in `.enabled(if:)` traits, so swift-testing reports them as
skipped rather than recording a failure. Read "23/23" as a claim about a
machine with Swift 6.3+ and NDK r27+ installed; on a bare machine expect the
same run to pass with three skipped. Suite-by-suite map:
[`RUNBOOK.md`](RUNBOOK.md) § Tests.

## Status

Shipped. It is the second SwiftStitch package in this repo and the host of
the Swift × Android alongside-pass (`alongside`). The one-command wrapper around
it is the `swiftstitch` package. `nitrogen-swift-spec-input` is untouched v0.3
work and hosts nothing in this pipeline. See the root README's package table.
