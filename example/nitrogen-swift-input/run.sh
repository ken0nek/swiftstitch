#!/usr/bin/env bash
# End-to-end pipeline runner for the nitrogen-swift-input example.
#
#   1. nitrogen-swift-input emit  →  specs/Counter.nitro.ts + specs/Counter.ir.json
#   2. bun nitrogen specs         →  nitrogen/generated/{shared,ios}/...
#
# Re-runnable. Wipes the previous outputs first so re-runs reflect the
# current Swift source and nitro.json verbatim.

set -euo pipefail

EX_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$EX_DIR/../.." && pwd)"

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

cd "$EX_DIR"

echo "==> Cleaning previous outputs"
rm -rf specs nitrogen

echo "==> Step 1: nitrogen-swift-input emit (Hybrid<Name>.swift  →  .nitro.ts + IR)"
# Zero-flag form: globs `swift/Hybrid*.swift`, writes to `specs/`, reads
# per-spec platforms from `nitro.json` autolinking. Equivalent to the
# explicit form:
#   "$CLI" emit --input swift/HybridCounter.swift --out specs --out-json specs --ios swift
"$CLI" emit

echo
echo "==> Step 2: bun nitrogen specs (.nitro.ts  →  C++/Swift bridge)"
"$NITROGEN" specs

echo
echo "==> Generated tree:"
find specs nitrogen -type f | sort
