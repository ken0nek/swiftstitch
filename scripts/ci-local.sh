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
# nitrogen-swift-embedded's compile and end-to-end tests FAIL (not skip) when
# Swift 6.3+ or the Android NDK are absent. Report up front so a red run is
# not misread as a code regression.
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
  echo "  swift 6.3+ : NOT FOUND — nitrogen-swift-embedded compile tests will FAIL"
fi

if compgen -G "$HOME/Library/Android/sdk/ndk/*/toolchains/llvm/prebuilt/*/bin" >/dev/null; then
  echo "  android ndk: $(ls -d "$HOME"/Library/Android/sdk/ndk/* | tail -1)"
else
  echo "  android ndk: NOT FOUND — the end-to-end link test will FAIL"
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

if (( ${#failed[@]} > 0 )); then
  echo "FAILED: ${failed[*]}"
  exit 1
fi

echo "All ${#packages[@]} package(s) passed."
