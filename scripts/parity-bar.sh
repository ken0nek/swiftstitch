#!/usr/bin/env bash
# The parity bar: drives the full SwiftStitch pipeline into a debug APK on a
# live arm64-v8a emulator and proves the two things ci-local.sh cannot —
# the shipped .so pulls in no Swift runtime (see ALLOWED_NEEDED below), and
# the module answers a real JS call correctly. Needs Gradle, the Android
# NDK, and a booted AVD, so it is deliberately NOT part of ci-local.sh, which
# stays fast and toolchain-independent. Exit 0 iff every stage below passes.
set -uo pipefail

fail() {
  echo "PARITY BAR: FAIL ($1)" >&2
  exit 1
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)" || fail "mktemp -d failed"
trap 'rm -rf "$WORK"' EXIT

# Captured before Preflight below overwrites the script's own JAVA_HOME (to
# the JDK 21 that runs Gradle) — find_jdk17_home checks whether the
# invoking shell's original JAVA_HOME already happens to be a JDK 17.
AMBIENT_JAVA_HOME="${JAVA_HOME:-}"

# --- Paths — nothing below this block is ambient ---------------------------

SWIFTC="$HOME/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swiftc"
NDK_READELF="$(ls "$HOME"/Library/Android/sdk/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-readelf 2>/dev/null | tail -1)"
EMULATOR="$HOME/Library/Android/sdk/emulator/emulator"

MODULE_DIR="$REPO_ROOT/example/math-module"
CLI="$REPO_ROOT/packages/swiftstitch/src/cli.ts"
INPUT_BIN="$REPO_ROOT/packages/nitrogen-swift-input/.build/release/nitrogen-swift-input"
EMBEDDED_BIN="$REPO_ROOT/packages/nitrogen-swift-embedded/.build/release/nitrogen-swift-embedded"

RN_ANDROID_DIR="$REPO_ROOT/example/rn-app/android"
BUILD_GRADLE="$RN_ANDROID_DIR/app/build.gradle"
APK="$REPO_ROOT/example/rn-app/android/app/build/outputs/apk/debug/app-debug.apk"
SO="$WORK/apk/lib/arm64-v8a/libNitroMath.so"

LOG_TAG="SwiftStitchParity"
EXPECTED_LINE="$LOG_TAG: sum=5 product=20"

# Every DT_NEEDED entry the shipped libNitroMath.so is permitted to carry, in
# two tiers:
#
#   1. bionic / NDK system libraries — the freestanding floor. A standalone
#      Embedded-Swift .so needs nothing else, which is what
#      Tests/.../EndToEndIntegrationTests.swift links and asserts on.
#   2. the React Native + Nitro shared libraries that EVERY nitro module
#      links. libNitroMath.so is a real nitro module, not a freestanding .so:
#      NitroMath+autolinking.cmake target_link_libraries() it against
#      fbjni::fbjni, ReactAndroid::jsi, react-native-nitro-modules::NitroModules
#      and (RN >= 0.76, and this repo is on 0.85.2) ReactAndroid::reactnative —
#      all prefab SHARED libraries whose symbols are referenced out-of-line, so
#      --as-needed cannot elide them. None of them is Swift; their presence is
#      expected and says nothing about the runtime claim.
#
# Tier 2 was derived from that CMake, not read off a built APK, so treat it as
# a PREDICTION. An entry outside this list is much more likely to be another
# legitimate RN library than a defect — the failure message below says so.
ALLOWED_NEEDED=(
  # tier 1 — bionic / NDK
  libc.so libm.so libdl.so liblog.so libandroid.so libc++_shared.so
  # tier 2 — React Native + Nitro
  libNitroModules.so libfbjni.so libjsi.so libreactnative.so
)

# --- Preflight — fail early, naming what is missing -------------------------
#
# Inlined from the plan's Preconditions section. Mandatory for the reasons in
# Task 4 Step 8: the ambient JAVA_HOME is stale (points at an uninstalled
# openjdk@17 cellar path), and a full-ABI Gradle build hits the generated
# CMake fragment's FATAL_ERROR on x86 (see GRADLE_ARCH_FLAG below).
resolve_java_home() {
  local h
  h="$(mise where java 2>/dev/null)" && [ -x "$h/bin/java" ] && { echo "$h"; return 0; }
  h="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  [ -x "$h/bin/java" ] && { echo "$h"; return 0; }
  return 1
}

# A JDK 17 *separate* from JAVA_HOME's JDK 21. React Native's Gradle plugin's
# own included build declares `kotlin { jvmToolchain(17) }` and compiles
# before and independently of anything this project sets. Without a JDK 17
# already on the machine, Gradle falls through to toolchain
# auto-provisioning via `foojay-resolver-convention` 0.5.0 (pinned inside
# node_modules), which crashes on the wrapper's Gradle 9.3.1 with an
# unreadable `JvmVendorSpec.IBM_SEMERU` NoSuchFieldError instead of
# downloading one. This check turns that crash into a one-line, actionable
# preflight message; it does not provision anything.
#
# Multiple probes because "install a JDK 17" is genuinely ambiguous — verified
# live on this machine: `mise where java@temurin-17` (vendor-qualified, what
# our own remediation message suggests) correctly resolves once installed
# (proven by the analogous `mise where java@temurin-21` against the JDK 21
# already here), but the shorter, equally natural `mise use java@17` installs
# a *different*, non-Temurin-branded artifact (`mise latest java@17` ->
# `17.0.2`, vs. `mise latest java@temurin-17` -> `temurin-17.0.19+10`) that
# the vendor-qualified probe alone would miss. The Homebrew probe exists
# because this exact machine has the matching failure mode already recorded
# in notes.md: a dangling `/Library/Java/JavaVirtualMachines/openjdk.jdk`
# symlink left behind by an since-uninstalled `openjdk@17` formula.
find_jdk17_home() {
  local h
  h="$(mise where java@temurin-17 2>/dev/null)" && [ -x "$h/bin/java" ] && { echo "$h"; return 0; }
  h="$(mise where java@17 2>/dev/null)" && [ -x "$h/bin/java" ] && { echo "$h"; return 0; }
  h="$(/usr/libexec/java_home -v 17 2>/dev/null)" && [ -x "$h/bin/java" ] && { echo "$h"; return 0; }
  h="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  [ -x "$h/bin/java" ] && { echo "$h"; return 0; }
  for h in "$HOME"/.jdks/*17*; do
    [[ -e "$h" ]] || continue
    [ -x "$h/Contents/Home/bin/java" ] && { echo "$h/Contents/Home"; return 0; }
    [ -x "$h/bin/java" ] && { echo "$h"; return 0; }
  done
  for h in "$HOME"/.sdkman/candidates/java/*17*; do
    [[ -e "$h" ]] || continue
    [ -x "$h/bin/java" ] && { echo "$h"; return 0; }
  done
  if [[ -n "$AMBIENT_JAVA_HOME" && -x "$AMBIENT_JAVA_HOME/bin/java" ]]; then
    "$AMBIENT_JAVA_HOME/bin/java" -version 2>&1 | grep -q '"17\.' && { echo "$AMBIENT_JAVA_HOME"; return 0; }
  fi
  return 1
}

echo "== preflight =="

[[ -x "$SWIFTC" ]] || fail "swiftc not found at $SWIFTC — install the Swift 6.3.1 toolchain"
echo "  swiftc      : $SWIFTC"

[[ -n "$NDK_READELF" && -x "$NDK_READELF" ]] || fail "llvm-readelf not found under ~/Library/Android/sdk/ndk/*/ — install Android NDK r27+"
echo "  ndk readelf : $NDK_READELF"

command -v adb >/dev/null 2>&1 || fail "adb not found on PATH — install Android platform-tools"
echo "  adb         : $(command -v adb)"

command -v unzip >/dev/null 2>&1 || fail "unzip not found on PATH"
echo "  unzip       : $(command -v unzip)"

JAVA_HOME="$(resolve_java_home)" || fail "no JDK 21 — see plan Preconditions (pin one with 'mise use java@temurin-21', or install Android Studio)"
export JAVA_HOME
"$JAVA_HOME/bin/java" -version >/dev/null 2>&1 || fail "\"$JAVA_HOME/bin/java\" -version failed"
echo "  java 21     : $JAVA_HOME"

if jdk17_home="$(find_jdk17_home)"; then
  echo "  java 17     : $jdk17_home"
else
  fail "no JDK 17 found — React Native's Gradle plugin requires a JDK 17 toolchain (separate from the JDK 21 that runs Gradle itself) to compile its own included build; without one, Gradle's toolchain auto-provisioning crashes instead of fetching it. Install one with \`mise install java@temurin-17\` — NOT \`mise use\`, which would rewrite this repo's committed .mise.toml pin from temurin-21 to temurin-17 and change the JDK that runs Gradle. Then re-run."
fi

[[ -x "$EMULATOR" ]] || fail "emulator binary not found at $EMULATOR — install the Android Emulator SDK component"
echo "  emulator    : $EMULATOR"

# Check the AVD's actual ABI by reading its config rather than trusting the
# name — an x86_64 "Medium_Phone"-alike would otherwise pass silently.
# An AVD's *name* is its .ini filename, NOT its .avd directory name — the two
# routinely differ (Android Studio's "Medium_Phone_API_36.1" ships a
# Medium_Phone.avd data dir). Deriving the name from the directory yields a name
# `emulator -avd` rejects with "Unknown AVD name", after the build has already
# run. So enumerate names the emulator itself admits, then follow each one's
# .ini `path=` to the config that records the ABI.
AVD_NAME=""
AVD_CONFIG=""
while IFS= read -r candidate; do
  [[ -n "$candidate" ]] || continue
  ini="$HOME/.android/avd/$candidate.ini"
  [[ -f "$ini" ]] || continue
  avd_path="$(sed -n 's/^path=//p' "$ini" | head -1)"
  [[ -n "$avd_path" && -f "$avd_path/config.ini" ]] || continue
  if grep -q 'abi.type=arm64-v8a' "$avd_path/config.ini"; then
    AVD_NAME="$candidate"
    AVD_CONFIG="$avd_path/config.ini"
    break
  fi
done < <("$EMULATOR" -list-avds 2>/dev/null)
[[ -n "$AVD_NAME" ]] || fail "no arm64-v8a AVD found — 'emulator -list-avds' lists no AVD whose config.ini has abi.type=arm64-v8a. Create one in Android Studio's Device Manager."
echo "  avd         : $AVD_NAME ($AVD_CONFIG)"

GRADLE_ARCH_FLAG="-PreactNativeArchitectures=arm64-v8a"

# NITRO_SWIFTC must stay exported through both Stage 1 (swiftstitch build,
# which does not itself compile Swift but must succeed before Gradle runs)
# and Stage 2 (the Gradle/CMake build, which is where swiftc actually runs —
# the generated NitroMath+swift-embedded.cmake fragment FATAL_ERRORs at
# configure time if ENV{NITRO_SWIFTC} is unset).
export NITRO_SWIFTC="$SWIFTC"

# --- Stage 1: swiftstitch build (example/math-module) ----------------------
echo
echo "== stage 1: swiftstitch build (example/math-module) =="

for pkg in nitrogen-swift-input nitrogen-swift-embedded; do
  bin="$REPO_ROOT/packages/$pkg/.build/release/$pkg"
  if [[ ! -x "$bin" ]]; then
    echo "  building release binary: $pkg"
    (cd "$REPO_ROOT/packages/$pkg" && swift build -c release) || fail "swift build -c release failed for $pkg"
  fi
done

# NEVER substitute this with a bare `bunx nitrogen`. That is only nitrogen's
# half of the pipeline: it neither re-derives the IR from the Swift source
# (nitrogen-swift-input emit) nor writes the three alongside outputs — the
# CMake fragment, the C++ glue header, the CBridge Swift file. `swiftstitch
# build` runs all three steps in one invocation. Those three files do now
# survive a bare `bunx nitrogen` — they live in swiftstitch/generated/, and
# nitrogen's cleanup sweep is scoped to nitrogen/generated/ — but they would
# be stale against a changed Swift source, which is what this bar measures.
bun "$CLI" build \
  --module-dir "$MODULE_DIR" \
  --input-bin "$INPUT_BIN" \
  --embedded-bin "$EMBEDDED_BIN" \
  || fail "swiftstitch build failed in example/math-module"

# Refresh rn-app's link tree before Gradle reads it. `bun install` materializes
# a `file:` dependency as a directory of per-file symlinks, NOT as one symlink
# to the module — so anything the module gained since the last install is
# simply absent from node_modules/react-native-swiftstitch-math/.
#
# This bites hard because AGP configures the module's CMake with
# CMAKE_SOURCE_DIR pointing at the *node_modules* copy, so the fragment's
# `${CMAKE_SOURCE_DIR}/../swiftstitch/generated/...` is resolved there. A
# missing link surfaces as "include could not find requested file" naming a
# path under node_modules, while the file plainly exists in the source module —
# a genuinely confusing half-hour. Observed for real when swiftstitch/ was
# first created after an install.
echo "  refreshing example/rn-app link tree (bun install)"
(cd "$REPO_ROOT/example/rn-app" && bun install) >/dev/null \
  || fail "bun install failed in example/rn-app"

# --- Stage 2: Gradle build (arm64-v8a only) ---------------------------------
echo
echo "== stage 2: gradlew :app:assembleDebug ($GRADLE_ARCH_FLAG) =="

# Restricted to arm64-v8a on the command line rather than editing committed
# gradle.properties (which declares all four ABIs): the generated CMake
# fragment message(FATAL_ERROR)s on any ABI outside its three known triples,
# and x86 is not among them, so a full-ABI build dies before arm64 is ever
# produced.
#
# -Porg.gradle.java.installations.paths registers $jdk17_home as a toolchain
# Gradle can discover without auto-provisioning — otherwise the preflight
# check above finds a JDK 17 in a location (e.g. a mise install) Gradle's own
# toolchain detection does not scan, and the crash this whole check exists to
# avoid happens anyway. This mechanism is UNVERIFIED end to end: no JDK 17
# exists on this machine to prove it against (see the fix report).
( cd "$RN_ANDROID_DIR" && ./gradlew :app:assembleDebug "$GRADLE_ARCH_FLAG" \
    "-Porg.gradle.java.installations.paths=$jdk17_home" ) \
  || fail "gradlew :app:assembleDebug failed"

# --- Stage 3: inspect the shipped library -----------------------------------
echo
echo "== stage 3: inspect shipped library =="

test -f "$APK" || fail "no APK produced at $APK"
mkdir -p "$WORK/apk" && unzip -o -q "$APK" -d "$WORK/apk" || fail "unzip failed for $APK"
test -f "$SO" || fail "no libNitroMath.so in APK"

NEEDED="$("$NDK_READELF" -d "$SO" | grep NEEDED)"
echo "$NEEDED"

# Guard against a vacuous pass: a stripped or wrong file is not a success.
[[ -n "$NEEDED" ]] || fail "no DT_NEEDED entries found in $SO — stripped or wrong file"

# Two assertions per entry, in this order, because they carry very different
# verdicts and must not be confused for one another:
#
#   1. a swift/foundation match is a PRODUCT defect — the headline claim is
#      violated. Asserted directly rather than by implication, so the claim
#      does not rest on ALLOWED_NEEDED being complete.
#   2. anything else outside ALLOWED_NEEDED is most likely a SCRIPT defect —
#      tier 2 of that list is a prediction. Still fails: an unknown dependency
#      must stop the bar rather than be waved through.
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  lib="$(sed -n 's/.*\[\(.*\)\].*/\1/p' <<<"$line")"
  [[ -n "$lib" ]] || fail "could not parse DT_NEEDED line: $line"

  case "$(tr '[:upper:]' '[:lower:]' <<<"$lib")" in
    # Swift corelibs whose names contain neither "swift" nor "foundation" are
    # named explicitly — they are just as much a runtime leak.
    *swift*|*foundation*|libdispatch.so|libblocksruntime.so|*icu*swift*)
      fail "SWIFT RUNTIME IN THE APK: '$lib' is a DT_NEEDED entry of $SO. Embedded Swift exists precisely so nothing like this ships. Do NOT add it to ALLOWED_NEEDED — find out why it linked."
      ;;
  esac

  allowed=0
  for candidate in "${ALLOWED_NEEDED[@]}"; do
    if [[ "$lib" == "$candidate" ]]; then
      allowed=1
      break
    fi
  done
  (( allowed == 1 )) || fail "DT_NEEDED entry '$lib' is not in ALLOWED_NEEDED (${ALLOWED_NEEDED[*]}). This is probably not a product defect: the React Native / Nitro half of that list was derived from NitroMath+autolinking.cmake rather than read off a built APK, so a legitimate RN library may simply be missing from it. Confirm '$lib' is expected for this module, then add it. (A Swift runtime entry is caught by the check above, not here.)"
done <<<"$NEEDED"

echo "  no Swift/Foundation runtime in DT_NEEDED; every entry is bionic or RN/Nitro"

# --- Stage 4: install, launch, and check logcat on a live emulator ---------
echo
echo "== stage 4: install + launch + logcat =="

APP_ID="$(sed -n 's/.*applicationId *"\([^"]*\)".*/\1/p' "$BUILD_GRADLE" | head -1)"
[[ -n "$APP_ID" ]] || fail "could not read applicationId from $BUILD_GRADLE"
echo "  app id      : $APP_ID"

# adb's serial-less commands (install/shell/logcat below) silently target
# "whatever adb picks" when more than one device is attached, which can
# misattribute a device mismatch as a pipeline defect. Require at most one
# before deciding whether to boot, so two attached devices fails immediately
# instead of spinning the boot-wait loop below for up to 300s on an
# unresolvable `adb shell getprop`.
device_lines() { adb devices | tail -n +2 | sed '/^[[:space:]]*$/d'; }

device_count="$(device_lines | wc -l | tr -d ' ')"
if (( device_count == 0 )); then
  echo "  no device online — booting $AVD_NAME"
  nohup "$EMULATOR" -avd "$AVD_NAME" -no-snapshot -no-boot-anim >"$WORK/emulator.log" 2>&1 &
elif (( device_count > 1 )); then
  fail "more than one adb device/emulator attached ($device_count) — the parity bar needs exactly one so its serial-less adb commands are unambiguous: $(device_lines | tr '\n' ';')"
fi

echo "  waiting for sys.boot_completed..."
waited=0
until [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')" == "1" ]]; do
  sleep 5
  waited=$((waited + 5))
  if (( waited >= 300 )); then
    echo "---- emulator boot log (tail), and current adb devices ----" >&2
    tail -n 40 "$WORK/emulator.log" >&2
    device_lines >&2
    echo "-------------------------------------------------------------" >&2
    fail "AVD $AVD_NAME did not report sys.boot_completed=1 within 300s"
  fi
done
echo "  device booted"

# Re-check post-boot: exactly one device, and it must actually be the
# arm64-v8a AVD — an attached phone or an x86_64 emulator would otherwise
# silently receive the arm64-only APK and die with UnsatisfiedLinkError,
# which without this check surfaces only later as a misleading "logcat never
# showed" verdict.
device_count="$(device_lines | wc -l | tr -d ' ')"
(( device_count == 1 )) || fail "expected exactly one adb device once booted, found $device_count: $(device_lines | tr '\n' ';')"

DEVICE_ABI="$(adb shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r\n')"
[[ "$DEVICE_ABI" == "arm64-v8a" ]] || fail "attached device reports ABI '$DEVICE_ABI', not arm64-v8a"

# Unguarded, this is a false-PASS vector: if `logcat -c` silently fails (it
# does on some images) while a previous run's EXPECTED_LINE is still in the
# ring buffer, the poll below would match a stale line and report PASS
# without this build ever emitting it — the one check whose entire job is
# falsifiability must not itself fail silently.
adb logcat -c || fail "adb logcat -c failed"
adb install -r "$APK" || fail "adb install failed"
# Not redirected: on failure to launch, monkey's diagnostic ("No activities
# found to run, monkey aborted.") goes to stdout, and monkey's exit code is
# not reliably non-zero on that failure — leaving stdout visible is often
# the only signal.
adb shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 || fail "failed to launch $APP_ID"

# Poll up to ~30s for the line to appear. Matching the full EXPECTED_LINE
# (not a bare "5") is what makes this assertion falsifiable.
found=0
for _ in $(seq 1 30); do
  if adb logcat -d | grep -F "$EXPECTED_LINE" >/dev/null; then
    found=1
    break
  fi
  sleep 1
done
(( found == 1 )) || fail "logcat never showed: $EXPECTED_LINE"
echo "  logcat      : $EXPECTED_LINE"

echo
echo "PARITY BAR: PASS"
