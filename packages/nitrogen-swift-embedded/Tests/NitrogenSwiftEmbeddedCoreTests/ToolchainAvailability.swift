import Foundation

/// Static probes for `.enabled(if:)` traits. Swift-testing evaluates trait
/// conditions once per run, so these must not depend on test-local state.
enum ToolchainAvailability {
    static var hasSwift63: Bool {
        if ProcessInfo.processInfo.environment["SWIFTSTITCH_FORCE_NO_TOOLCHAIN"] != nil { return false }
        return locateSwift63Swiftc() != nil
    }

    static var hasAndroidNDK: Bool {
        if ProcessInfo.processInfo.environment["SWIFTSTITCH_FORCE_NO_TOOLCHAIN"] != nil { return false }
        return locateAndroidClang() != nil
    }
}

/// Locates a Swift 6.3+ `swiftc`, if installed. Embedded Swift's `@c` peer
/// exports shipped in 6.3, so the compile-and-link tests need this exact
/// toolchain on disk.
///
/// Consolidated from three near-identical definitions that used to live one
/// per test file (`CLITests`, `EmbeddedCompilerTests`,
/// `EndToEndIntegrationTests`). All three listed the same candidates
/// including `swift-latest.xctoolchain`; that candidate is dropped here since
/// "latest" is not guaranteed to be 6.3.x and could make this probe report a
/// false positive.
func locateSwift63Swiftc() -> URL? {
    let candidates = [
        "~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swiftc",
        "~/Library/Developer/Toolchains/swift-6.3.0-RELEASE.xctoolchain/usr/bin/swiftc",
    ]
    for raw in candidates {
        let expanded = NSString(string: raw).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
    }
    return nil
}

/// Locates the Android NDK's aarch64 `clang++`, if installed.
func locateAndroidClang() -> URL? {
    guard let root = try? ndkRoot() else { return nil }
    let prebuilt = root.appendingPathComponent("toolchains/llvm/prebuilt")
    guard let archDirs = try? FileManager.default.contentsOfDirectory(atPath: prebuilt.path) else {
        return nil
    }
    for arch in archDirs {
        let bin = prebuilt.appendingPathComponent(arch).appendingPathComponent("bin")
        // Try API levels 28..36, descending.
        for api in (28...36).reversed() {
            let candidate = bin.appendingPathComponent("aarch64-linux-android\(api)-clang++")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
    }
    return nil
}

/// Locates the highest-versioned Android NDK root under the usual SDK
/// install paths. Also called directly by `EndToEndIntegrationTests` to
/// resolve `llvm-readelf` / `llvm-nm`, so it stays a shared free function
/// rather than folding into `locateAndroidClang()`.
func ndkRoot() throws -> URL {
    let candidates = [
        "~/Library/Android/sdk/ndk",
        "/opt/android-sdk/ndk",
    ]
    for raw in candidates {
        let dir = NSString(string: raw).expandingTildeInPath
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
        // Pick highest version.
        let sorted = entries.sorted().reversed()
        for entry in sorted {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(entry)
            let prebuilt = candidate
                .appendingPathComponent("toolchains/llvm/prebuilt")
            if FileManager.default.fileExists(atPath: prebuilt.path) {
                return candidate
            }
        }
    }
    struct NoNDK: Error, CustomStringConvertible { var description: String { "NDK not found" } }
    throw NoNDK()
}
