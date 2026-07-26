#!/usr/bin/env bash
# Run the codegen pipeline for this nitro module.
#
#   1. nitrogen-swift-input emit  →  specs/Counter.nitro.ts + specs/Counter.ir.json
#   2. bun nitrogen specs         →  nitrogen/generated/{shared,ios}/...
#
# Re-run whenever swift/ or nitro.json changes. The `specs/` and
# `nitrogen/generated/` outputs are committed alongside this package — they
# ship to consumers, who never run codegen themselves (they just `bun add`
# this package and run `pod install`).

set -euo pipefail

PKG_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$PKG_DIR/../.." && pwd)"

CLI="$REPO_ROOT/packages/nitrogen-swift-input/.build/debug/nitrogen-swift-input"
NITROGEN="$REPO_ROOT/node_modules/.bin/nitrogen"

if [[ ! -x "$CLI" ]]; then
  echo "==> Building nitrogen-swift-input"
  swift build --package-path "$REPO_ROOT/packages/nitrogen-swift-input"
fi

if [[ ! -x "$NITROGEN" ]]; then
  echo "error: $NITROGEN not found. Run 'bun install' from the repo root." >&2
  exit 1
fi

cd "$PKG_DIR"

echo "==> Cleaning previous outputs"
rm -rf specs nitrogen

echo "==> Step 1: nitrogen-swift-input emit"
# Zero-flag form: inputs glob `swift/Hybrid*.swift`, outputs to `specs/`,
# per-spec platforms come from `nitro.json` autolinking. The explicit form
# below is equivalent and serves as documentation:
#   "$CLI" emit --input swift/HybridCounter.swift --out specs --out-json specs --ios swift --android kotlin
"$CLI" emit

echo
echo "==> Step 2: bun nitrogen specs"
"$NITROGEN" specs
