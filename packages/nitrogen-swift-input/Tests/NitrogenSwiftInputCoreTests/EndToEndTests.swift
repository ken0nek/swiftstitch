import Foundation
import Testing
@testable import NitrogenSwiftInputCore

@Suite("Phase 1A.5 — end-to-end: Swift → .nitro.ts → nitrogen")
struct EndToEndTests {
    @Test("HybridSimpleMath fixture flows through CLI and nitrogen")
    func endToEnd() throws {
        let workspaceRoot = try resolveWorkspaceRoot()
        let cliBinary = workspaceRoot
            .appendingPathComponent("packages/nitrogen-swift-input/.build/debug/nitrogen-swift-input")
        try #require(
            FileManager.default.fileExists(atPath: cliBinary.path),
            "CLI binary not built; run `swift build` first."
        )
        let nitrogenBinary = workspaceRoot
            .appendingPathComponent("node_modules/.bin/nitrogen")
        try #require(
            FileManager.default.fileExists(atPath: nitrogenBinary.path),
            "nitrogen binary not present at \(nitrogenBinary.path)"
        )

        // Temp module dir under packages/nitrogen-swift-input/.build/e2e/ so
        // node module resolution walks up to the workspace root and finds
        // react-native-nitro-modules / nitrogen / etc.
        let workDir = workspaceRoot
            .appendingPathComponent("packages/nitrogen-swift-input/.build/e2e")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // 1. nitro.json
        let nitroJSON = """
        {
          "$schema": "https://nitro.margelo.com/nitro.schema.json",
          "cxxNamespace": ["e2etest"],
          "ios": { "iosModuleName": "E2ETest" },
          "android": { "androidNamespace": ["e2etest"], "androidCxxLibName": "E2ETest" },
          "autolinking": {
            "SimpleMath": {
              "ios": {
                "language": "swift",
                "implementationClassName": "HybridSimpleMath"
              }
            }
          },
          "ignorePaths": ["**/node_modules"],
          "gitAttributesGeneratedFlag": false
        }
        """
        try nitroJSON.write(
            to: workDir.appendingPathComponent("nitro.json"),
            atomically: true,
            encoding: .utf8
        )

        // 2. Drop the user-authored Swift fixture into ios/.
        let iosDir = workDir.appendingPathComponent("ios")
        try FileManager.default.createDirectory(at: iosDir, withIntermediateDirectories: true)
        let fixtureURL = try fixtureURL("HybridSimpleMath.swift")
        let swiftFile = iosDir.appendingPathComponent("HybridSimpleMath.swift")
        try FileManager.default.copyItem(at: fixtureURL, to: swiftFile)

        // 3. Run our CLI to produce src/specs/SimpleMath.nitro.ts.
        let specsDir = workDir.appendingPathComponent("src/specs")
        try FileManager.default.createDirectory(at: specsDir, withIntermediateDirectories: true)
        let cliResult = try runProcess(
            executable: cliBinary,
            arguments: [
                "emit",
                "--input", swiftFile.path,
                "--out", specsDir.path,
                "--ios", "swift",
            ],
            cwd: workDir
        )
        try #require(cliResult.exitCode == 0, "nitrogen-swift-input failed:\nstdout: \(cliResult.stdout)\nstderr: \(cliResult.stderr)")

        let generatedSpec = specsDir.appendingPathComponent("SimpleMath.nitro.ts")
        #expect(FileManager.default.fileExists(atPath: generatedSpec.path))

        let generatedContents = try String(contentsOf: generatedSpec, encoding: .utf8)
        #expect(generatedContents.contains("export interface SimpleMath extends HybridObject<{ ios: 'swift' }>"))
        #expect(generatedContents.contains("add(a: number, b: number): number"))
        #expect(generatedContents.contains("subtract(a: Int64, b: Int64): Int64"))

        // 4. Run nitrogen against the temp module.
        let nitrogenResult = try runProcess(
            executable: nitrogenBinary,
            arguments: [],
            cwd: workDir
        )
        try #require(
            nitrogenResult.exitCode == 0,
            "nitrogen failed:\nstdout: \(nitrogenResult.stdout)\nstderr: \(nitrogenResult.stderr)"
        )

        // 5. Verify nitrogen artifacts exist.
        let generatedDir = workDir.appendingPathComponent("nitrogen/generated")
        let expectedArtifacts = [
            "shared/c++/HybridSimpleMathSpec.hpp",
            "shared/c++/HybridSimpleMathSpec.cpp",
            "ios/swift/HybridSimpleMathSpec.swift",
            "ios/swift/HybridSimpleMathSpec_cxx.swift",
            "ios/c++/HybridSimpleMathSpecSwift.hpp",
            "ios/c++/HybridSimpleMathSpecSwift.cpp",
        ]
        for relative in expectedArtifacts {
            let full = generatedDir.appendingPathComponent(relative)
            #expect(
                FileManager.default.fileExists(atPath: full.path),
                "missing nitrogen artifact: \(relative)"
            )
        }

        // 6. Spot-check shared C++ header content.
        let hpp = try String(
            contentsOf: generatedDir.appendingPathComponent("shared/c++/HybridSimpleMathSpec.hpp"),
            encoding: .utf8
        )
        #expect(hpp.contains("class HybridSimpleMathSpec"))
        #expect(hpp.contains("add"))
        #expect(hpp.contains("subtract"))
    }

    private func resolveWorkspaceRoot() throws -> URL {
        let bundleURL = Bundle.module.bundleURL
        var candidate: URL? = bundleURL
        for _ in 0..<10 {
            guard let dir = candidate else { break }
            let packageJSON = dir.appendingPathComponent("package.json")
            let pkgDir = dir.appendingPathComponent("packages")
            if FileManager.default.fileExists(atPath: packageJSON.path),
               FileManager.default.fileExists(atPath: pkgDir.path) {
                return dir
            }
            candidate = dir.deletingLastPathComponent()
            if candidate == dir { break }
        }
        struct WorkspaceRootError: Error, CustomStringConvertible {
            var description: String { "could not resolve workspace root from test bundle" }
        }
        throw WorkspaceRootError()
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            struct FixtureError: Error, CustomStringConvertible {
                let name: String
                var description: String { "missing fixture: \(name)" }
            }
            throw FixtureError(name: name)
        }
        return url
    }
}

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

func runProcess(executable: URL, arguments: [String], cwd: URL) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = cwd
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    process.waitUntilExit()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    return ProcessResult(
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
}
