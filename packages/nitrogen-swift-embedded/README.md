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
- **It does not generate the Android CMake fragment.** That lives in nitrogen
  core and arrives with the alongside-pass (`nitrogen-swift-spec-input`).

Until that alongside-pass lands, `bun nitro` does not drive this pipeline —
you invoke the CLI yourself, or from your own build script.

## Toolchain

| | |
|---|---|
| Build this package | Swift **6.2+** (`swift-tools-version: 6.0`) |
| Run `compile` | Swift **6.3+** — `@c` and Embedded mode are 6.3-only |
| Link the `.o` | Android **NDK r27+** (not invoked by this CLI) |

Point `--swiftc` at an explicit 6.3.x toolchain. The test helpers fall back
through `swift-6.3.1-RELEASE` → `swift-6.3.0-RELEASE` →
`swift-latest.xctoolchain`, and `swift-latest` is a symlink that may resolve
below 6.3 — which fails confusingly rather than cleanly.

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
Only `aarch64` (Android `arm64-v8a`) has been live-tested; multi-ABI is out of
scope for now.

## Tests

```sh
swift test --package-path packages/nitrogen-swift-embedded
```

15 tests. Twelve are pure emitter/golden checks; two invoke a real Swift 6.3
`swiftc`; one runs the full pipeline through an NDK link and asserts
`DT_NEEDED` is bionic-only with the `@c` symbols exported.

**Those three do not skip without a toolchain — they fail.** Their guards use
`Issue.record("...; skipping")`, which in swift-testing records a *failure*.
Read "15/15" as a claim about a machine with Swift 6.3+ and NDK r27+
installed. Suite-by-suite map: [`RUNBOOK.md`](RUNBOOK.md) § Tests.

## Status

Shipped — the second SwiftStitch package in this repo. What's still missing is
the automation around it: the alongside-pass that makes `bun nitro` invoke
this pipeline lands with `nitrogen-swift-spec-input`. See the root README's
package table.
