import Testing
import Foundation
@testable import NitrogenSwiftEmbeddedCore
@testable import NitrogenSwiftInputCore

@Suite("alongside pass")
struct AlongsideTests {
    @Test("no swiftstitch block is a no-op, not an error")
    func noBlockNoOps() throws {
        let dir = try TempDir()
        try dir.writeNitroJSON(includingSwiftStitchBlock: false)
        let written = try AlongsideRunner.run(
            nitroJSONPath: dir.nitroJSON, outDir: dir.outDir, irDir: dir.specs)
        #expect(written.isEmpty)
    }

    @Test("emits all three files at the contracted paths")
    func emitsThreeFiles() throws {
        let dir = try TempDir()
        try dir.writeFixture()   // nitro.json with block + SimpleMath.ir.json
        let written = try AlongsideRunner.run(
            nitroJSONPath: dir.nitroJSON, outDir: dir.outDir, irDir: dir.specs)
        #expect(written.count == 3)
        #expect(FileManager.default.fileExists(atPath:
            dir.outDir + "/swift/HybridSimpleMath+CBridge.swift"))
        #expect(FileManager.default.fileExists(atPath:
            dir.outDir + "/c++/HybridSimpleMath.hpp"))
        #expect(FileManager.default.fileExists(atPath:
            dir.outDir + "/EmbeddedTest+swift-embedded.cmake"))
    }

    @Test("cmake fragment bakes in userSwiftDir and calls the compile function per class")
    func cmakeFragmentShape() {
        let cmake = CMakeFragmentEmitter.emit(
            hostLibraryName: "EmbeddedTest", userSwiftDir: "swift",
            classNames: ["HybridSimpleMath"])
        #expect(cmake.contains("nitro_compile_embedded_swift(HybridSimpleMath)"))
        #expect(cmake.contains(#"set(_NITRO_USER_SWIFT_DIR "${CMAKE_SOURCE_DIR}/../swift")"#))
        #expect(cmake.contains(#"$ENV{NITRO_SWIFTC}"#))
        // userSwiftDir is baked in at generate time; only NITRO_SWIFTC is an
        // env var. Assert on `ENV{...}` specifically — the local CMake
        // variable `${_NITRO_USER_SWIFT_DIR}` legitimately appears.
        #expect(!cmake.contains(#"ENV{NITRO_USER_SWIFT_DIR}"#))
        #expect(cmake.contains("target_sources(EmbeddedTest PRIVATE"))
        // Load-bearing: the glue headers no longer sit on nitrogen's include
        // path, so without this line nitrogen's own <Lib>OnLoad.cpp cannot
        // resolve `#include "Hybrid<Foo>.hpp"`.
        #expect(cmake.contains(
            #"target_include_directories(EmbeddedTest PRIVATE "${CMAKE_SOURCE_DIR}/../swiftstitch/generated/c++")"#))
    }

    @Test("re-running is byte-identical")
    func idempotent() throws {
        let dir = try TempDir()
        try dir.writeFixture()
        _ = try AlongsideRunner.run(nitroJSONPath: dir.nitroJSON, outDir: dir.outDir, irDir: dir.specs)
        let first = try dir.snapshotGenerated()
        _ = try AlongsideRunner.run(nitroJSONPath: dir.nitroJSON, outDir: dir.outDir, irDir: dir.specs)
        #expect(try dir.snapshotGenerated() == first)
    }

    @Test("spec listed in swiftOnAndroid but missing from autolinking is a hard error")
    func unknownSpecErrors() throws {
        let dir = try TempDir()
        try dir.writeFixture(swiftOnAndroid: ["NotThere"])
        #expect(throws: AlongsideError.self) {
            try AlongsideRunner.run(nitroJSONPath: dir.nitroJSON, outDir: dir.outDir, irDir: dir.specs)
        }
    }

    @Test("android language other than c++ is a hard error")
    func wrongLanguageErrors() throws {
        let dir = try TempDir()
        try dir.writeFixture(androidLanguage: "kotlin")
        #expect(throws: AlongsideError.self) {
            try AlongsideRunner.run(nitroJSONPath: dir.nitroJSON, outDir: dir.outDir, irDir: dir.specs)
        }
    }

    @Test("missing IR JSON is a hard error naming the path")
    func missingIRErrors() throws {
        let dir = try TempDir()
        try dir.writeFixture(writeIR: false)
        #expect(throws: AlongsideError.self) {
            try AlongsideRunner.run(nitroJSONPath: dir.nitroJSON, outDir: dir.outDir, irDir: dir.specs)
        }
    }
}

/// Scratch module layout: <root>/nitro.json, <root>/specs/, <root>/swift/,
/// <root>/swiftstitch/generated/. Removed on deinit.
final class TempDir {
    let root: String

    var nitroJSON: String { root + "/nitro.json" }
    var specs: String     { root + "/specs" }
    var outDir: String    { root + "/swiftstitch/generated" }

    private var userSwift: String { root + "/swift" }

    init() throws {
        root = NSTemporaryDirectory() + "nse-alongside-\(UUID().uuidString)"
        for dir in [root, specs, userSwift, outDir] {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
        }
    }

    deinit {
        try? FileManager.default.removeItem(atPath: root)
    }

    /// nitro.json only. `includingSwiftStitchBlock: false` omits the block.
    func writeNitroJSON(includingSwiftStitchBlock: Bool) throws {
        try writeNitroJSON(
            includingSwiftStitchBlock: includingSwiftStitchBlock,
            swiftOnAndroid: ["SimpleMath"],
            androidLanguage: "c++"
        )
    }

    /// The full happy-path module: nitro.json WITH the block, plus
    /// specs/SimpleMath.ir.json, plus swift/HybridSimpleMath.swift.
    /// Every parameter defaults to the happy path.
    func writeFixture(
        swiftOnAndroid: [String] = ["SimpleMath"],
        androidLanguage: String = "c++",
        writeIR: Bool = true
    ) throws {
        try writeNitroJSON(
            includingSwiftStitchBlock: true,
            swiftOnAndroid: swiftOnAndroid,
            androidLanguage: androidLanguage
        )

        // The pass only checks that the user's Swift file exists; content is
        // never parsed here (nitrogen-swift-input owns that).
        try """
        public final class HybridSimpleMath {
            public init() {}
            public func add(a: Double, b: Double) -> Double { a + b }
            public func multiply(a: Double, b: Double) -> Double { a * b }
        }
        """.write(toFile: userSwift + "/HybridSimpleMath.swift",
                  atomically: true, encoding: .utf8)

        guard writeIR else { return }
        let ir = HybridObjectIR(
            className: "HybridSimpleMath",
            platforms: [PlatformBinding(platform: .android, language: .swift)],
            methods: [
                MethodIR(name: "add", parameters: [
                    ParameterIR(label: "a", type: .double),
                    ParameterIR(label: "b", type: .double),
                ], returnType: .double, isThrowing: false),
                MethodIR(name: "multiply", parameters: [
                    ParameterIR(label: "a", type: .double),
                    ParameterIR(label: "b", type: .double),
                ], returnType: .double, isThrowing: false),
            ]
        )
        try IRJSONCodec.encode([ir])
            .write(to: URL(fileURLWithPath: specs + "/SimpleMath.ir.json"))
    }

    /// Sorted [relativePath: fileContents] over `outDir`, for equality.
    func snapshotGenerated() throws -> [String: String] {
        let base = URL(fileURLWithPath: outDir, isDirectory: true)
        guard let walker = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [:] }

        var snapshot: [String: String] = [:]
        for case let url as URL in walker {
            let isFile = try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile
            guard isFile == true else { continue }
            let relative = String(url.path.dropFirst(base.path.count + 1))
            snapshot[relative] = try String(contentsOf: url, encoding: .utf8)
        }
        return snapshot
    }

    // MARK: - nitro.json

    private func writeNitroJSON(
        includingSwiftStitchBlock: Bool,
        swiftOnAndroid: [String],
        androidLanguage: String
    ) throws {
        let specList = swiftOnAndroid.map { "\"\($0)\"" }.joined(separator: ", ")
        let block = includingSwiftStitchBlock ? """
        ,
          "swiftstitch": {
            "userSwiftDir": "swift",
            "swiftOnAndroid": [\(specList)]
          }
        """ : "\n"

        try """
        {
          "$schema": "https://nitro.margelo.com/nitro.schema.json",
          "cxxNamespace": ["embedded"],
          "ios": { "iosModuleName": "EmbeddedTest" },
          "android": { "androidNamespace": ["embedded"], "androidCxxLibName": "EmbeddedTest" },
          "autolinking": {
            "SimpleMath": {
              "ios":     { "language": "swift", "implementationClassName": "HybridSimpleMath" },
              "android": { "language": "\(androidLanguage)",   "implementationClassName": "HybridSimpleMath" }
            }
          }\(block)}
        """.write(toFile: nitroJSON, atomically: true, encoding: .utf8)
    }
}
