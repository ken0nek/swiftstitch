import Foundation
import Testing
@testable import NitrogenSwiftInputCore

/// `emit`'s default input discovery must honor `swiftstitch.userSwiftDir`.
///
/// Before this, the scan directory was a hardcoded `swift/` and nitro.json was
/// loaded only *after* inputs were resolved — so a module could declare
/// `userSwiftDir` and have `emit` ignore it, failing with "no Hybrid*.swift
/// files in swift/" while the sources sat where the config said they were.
@Suite("emit honors swiftstitch.userSwiftDir")
struct UserSwiftDirTests {
    /// `<root>/nitro.json` + `<root>/<swiftDir>/HybridSimpleMath.swift`.
    /// `swiftstitchBlock: nil` omits the block entirely.
    private func makeModule(swiftDir: String, userSwiftDir: String?) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ss-usd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let block = userSwiftDir.map {
            """
            ,
              "swiftstitch": { "userSwiftDir": "\($0)", "swiftOnAndroid": ["SimpleMath"] }
            """
        } ?? ""

        let nitroJSON = """
        {
          "cxxNamespace": ["usd"],
          "ios": { "iosModuleName": "USD" },
          "android": { "androidNamespace": ["usd"], "androidCxxLibName": "USD" },
          "autolinking": {
            "SimpleMath": {
              "ios":     { "language": "swift", "implementationClassName": "HybridSimpleMath" },
              "android": { "language": "c++",   "implementationClassName": "HybridSimpleMath" }
            }
          }\(block)
        }
        """
        try nitroJSON.write(
            to: root.appendingPathComponent("nitro.json"), atomically: true, encoding: .utf8)

        let sourcesDir = root.appendingPathComponent(swiftDir)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try """
        public final class HybridSimpleMath {
            public init() {}
            public func add(a: Double, b: Double) -> Double { a + b }
        }
        """.write(
            to: sourcesDir.appendingPathComponent("HybridSimpleMath.swift"),
            atomically: true, encoding: .utf8)

        return root
    }

    private func cliBinary() throws -> URL {
        var dir: URL? = Bundle.module.bundleURL
        for _ in 0..<10 {
            guard let d = dir else { break }
            let candidate = d.appendingPathComponent("nitrogen-swift-input")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            dir = d.deletingLastPathComponent()
            if dir == d { break }
        }
        struct NotBuilt: Error, CustomStringConvertible {
            var description: String { "nitrogen-swift-input binary not found; run `swift build` first" }
        }
        throw NotBuilt()
    }

    @Test("a non-default userSwiftDir is scanned")
    func honorsConfiguredDir() throws {
        let bin = try cliBinary()
        let root = try makeModule(swiftDir: "sources", userSwiftDir: "sources")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try runProcess(executable: bin, arguments: ["emit"], cwd: root)
        #expect(
            result.exitCode == 0,
            "emit should have scanned sources/:\nstdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("specs/SimpleMath.nitro.ts").path))
    }

    @Test("with no swiftstitch block the default swift/ is still scanned")
    func defaultsToSwiftDir() throws {
        let bin = try cliBinary()
        let root = try makeModule(swiftDir: "swift", userSwiftDir: nil)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try runProcess(executable: bin, arguments: ["emit"], cwd: root)
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("specs/SimpleMath.nitro.ts").path))
    }

    @Test("the error names the configured directory, not the hardcoded default")
    func errorNamesConfiguredDir() throws {
        let bin = try cliBinary()
        // Config says `sources`, but the Swift is in `swift/` — so discovery
        // must come up empty and say so about `sources`.
        let root = try makeModule(swiftDir: "swift", userSwiftDir: "sources")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try runProcess(executable: bin, arguments: ["emit"], cwd: root)
        #expect(result.exitCode != 0)
        #expect(
            result.stderr.contains("sources"),
            "error should name the configured dir; got: \(result.stderr)")
    }
}
