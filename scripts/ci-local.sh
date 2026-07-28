#!/usr/bin/env bash
# Runs the full local test suite across every Swift package in the repo.
# Exit 0 iff all suites pass. This is what CI will run once CI exists.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

packages=(
  nitrogen-swift-input
  nitrogen-swift-embedded
)

# --- Preflight -------------------------------------------------------------
# nitrogen-swift-embedded's compile and end-to-end tests SKIP (not fail) when
# Swift 6.3+ or the Android NDK are absent. Report up front so a run with
# fewer tests exercised is not misread as a code regression.
echo "== preflight =="

swiftc63=""
for candidate in \
  "$HOME/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swiftc" \
  "$HOME/Library/Developer/Toolchains/swift-6.3.0-RELEASE.xctoolchain/usr/bin/swiftc"
do
  if [[ -x "$candidate" ]]; then swiftc63="$candidate"; break; fi
done

if [[ -n "$swiftc63" ]]; then
  echo "  swift 6.3+ : $swiftc63"
else
  echo "  swift 6.3+ : NOT FOUND — nitrogen-swift-embedded compile tests will SKIP"
fi

if compgen -G "$HOME/Library/Android/sdk/ndk/*/toolchains/llvm/prebuilt/*/bin" >/dev/null; then
  echo "  android ndk: $(ls -d "$HOME"/Library/Android/sdk/ndk/* | tail -1)"
else
  echo "  android ndk: NOT FOUND — the end-to-end link test will SKIP"
fi
echo

# --- Test ------------------------------------------------------------------
failed=()
for pkg in "${packages[@]}"; do
  echo "== swift test: $pkg =="
  if (cd "$repo_root/packages/$pkg" && swift test); then
    echo "-- PASS: $pkg"
  else
    echo "-- FAIL: $pkg"
    failed+=("$pkg")
  fi
  echo
done

# --- TypeScript ------------------------------------------------------------
echo "== bun test: swiftstitch =="
if (cd "$repo_root/packages/swiftstitch" && bun test); then
  echo "-- PASS: swiftstitch (test)"
else
  echo "-- FAIL: swiftstitch (test)"
  failed+=("swiftstitch (test)")
fi
echo

echo "== typecheck: swiftstitch =="
if (cd "$repo_root/packages/swiftstitch" && bunx tsc --noEmit); then
  echo "-- PASS: swiftstitch (typecheck)"
else
  echo "-- FAIL: swiftstitch (typecheck)"
  failed+=("swiftstitch (typecheck)")
fi
echo

if (( ${#failed[@]} > 0 )); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi

echo "All checks passed."
