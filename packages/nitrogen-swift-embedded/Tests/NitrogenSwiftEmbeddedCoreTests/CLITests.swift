import Foundation
import Testing
@testable import NitrogenSwiftEmbeddedCore
@testable import NitrogenSwiftInputCore

@Suite("nitrogen-swift-embedded CLI emit")
struct CLITests {
    @Test("emits +CBridge.swift from IR JSON")
    func cliEmitProducesBridgeFile() throws {
        let workspaceRoot = try resolveWorkspaceRoot()
        let cli = workspaceRoot
            .appendingPathComponent("packages/nitrogen-swift-embedded/.build/debug/nitrogen-swift-embedded")
        try #require(
            FileManager.default.fileExists(atPath: cli.path),
            "CLI binary not built at \(cli.path); run `swift build` first."
        )

        let ir = HybridObjectIR(
            className: "HybridSimpleMath",
            platforms: [PlatformBinding(platform: .android, language: .swift)],
            methods: [
                MethodIR(
                    name: "add",
                    parameters: [
                        ParameterIR(label: "a", type: .double),
                        ParameterIR(label: "b", type: .double),
                    ],
                    returnType: .double,
                    isThrowing: false
                ),
                MethodIR(
                    name: "subtract",
                    parameters: [
                        ParameterIR(label: "a", type: .int64),
                        ParameterIR(label: "b", type: .int64),
                    ],
                    returnType: .int64,
                    isThrowing: false
                ),
            ]
        )
        let json = try IRJSONCodec.encode([ir])

        let workDir = workspaceRoot
            .appendingPathComponent("packages/nitrogen-swift-embedded/.build/cli-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let irFile = workDir.appendingPathComponent("simple.ir.json")
        try json.write(to: irFile)
        let outDir = workDir.appendingPathComponent("out")

        let result = try runProcess(
            executable: cli,
            arguments: ["emit", "--ir", irFile.path, "--out", outDir.path],
            cwd: workDir
        )
        try #require(
            result.exitCode == 0,
            "CLI failed:\nstdout: \(result.stdout)\nstderr: \(result.stderr)"
        )

        let bridgeFile = outDir.appendingPathComponent("HybridSimpleMath+CBridge.swift")
        #expect(FileManager.default.fileExists(atPath: bridgeFile.path))
        let contents = try String(contentsOf: bridgeFile, encoding: .utf8)
        #expect(contents.contains("@c"))
        #expect(contents.contains("public func HybridSimpleMath_create()"))
        #expect(contents.contains("public func HybridSimpleMath_destroy"))
        #expect(contents.contains("public func HybridSimpleMath_add"))
        #expect(contents.contains("public func HybridSimpleMath_subtract"))
    }

    @Test("emit-cpp subcommand produces C++ glue header")
    func cliEmitCppProducesHeader() throws {
        let workspaceRoot = try resolveWorkspaceRoot()
        let cli = workspaceRoot
            .appendingPathComponent("packages/nitrogen-swift-embedded/.build/debug/nitrogen-swift-embedded")
        try #require(FileManager.default.fileExists(atPath: cli.path))

        let ir = HybridObjectIR(
            className: "HybridSimpleMath",
            platforms: [PlatformBinding(platform: .android, language: .swift)],
            methods: [
                MethodIR(name: "add", parameters: [
                    ParameterIR(label: "a", type: .double),
                    ParameterIR(label: "b", type: .double),
                ], returnType: .double, isThrowing: false),
            ]
        )
        let workDir = workspaceRoot
            .appendingPathComponent("packages/nitrogen-swift-embedded/.build/cli-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let irFile = workDir.appendingPathComponent("simple.ir.json")
        try IRJSONCodec.encode([ir]).write(to: irFile)
        let outDir = workDir.appendingPathComponent("cpp-out")

        let result = try runProcess(
            executable: cli,
            arguments: [
                "emit-cpp",
                "--ir", irFile.path,
                "--out", outDir.path,
                "--namespace", "margelo::nitro::test",
            ],
            cwd: workDir
        )
        try #require(result.exitCode == 0, "emit-cpp failed: \(result.stderr)")

        let hppFile = outDir.appendingPathComponent("HybridSimpleMath.hpp")
        #expect(FileManager.default.fileExists(atPath: hppFile.path))
        let contents = try String(contentsOf: hppFile, encoding: .utf8)
        #expect(contents.contains("class HybridSimpleMath : public virtual HybridSimpleMathSpec"))
        #expect(contents.contains("extern double HybridSimpleMath_add(void* handle, double a, double b);"))
        #expect(contents.contains("namespace margelo::nitro::test {"))
    }

    @Test("compile subcommand drives swiftc end-to-end")
    func cliCompileProducesObject() throws {
        let workspaceRoot = try resolveWorkspaceRoot()
        let cli = workspaceRoot
            .appendingPathComponent("packages/nitrogen-swift-embedded/.build/debug/nitrogen-swift-embedded")
        try #require(FileManager.default.fileExists(atPath: cli.path))

        let swiftc = locateSwift63Swiftc()
        guard let swiftc else {
            Issue.record("Swift 6.3+ toolchain not installed; skipping")
            return
        }

        let workDir = workspaceRoot
            .appendingPathComponent("packages/nitrogen-swift-embedded/.build/cli-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let userSwift = workDir.appendingPathComponent("HybridSimpleMath.swift")
        try """
        public final class HybridSimpleMath {
            public init() {}
            public func add(a: Double, b: Double) -> Double { a + b }
            public func subtract(a: Int64, b: Int64) -> Int64 { a - b }
        }
        """.write(to: userSwift, atomically: true, encoding: .utf8)

        let ir = HybridObjectIR(
            className: "HybridSimpleMath",
            platforms: [PlatformBinding(platform: .android, language: .swift)],
            methods: [
                MethodIR(name: "add", parameters: [
                    ParameterIR(label: "a", type: .double),
                    ParameterIR(label: "b", type: .double),
                ], returnType: .double, isThrowing: false),
                MethodIR(name: "subtract", parameters: [
                    ParameterIR(label: "a", type: .int64),
                    ParameterIR(label: "b", type: .int64),
                ], returnType: .int64, isThrowing: false),
            ]
        )
        let irFile = workDir.appendingPathComponent("simple.ir.json")
        try IRJSONCodec.encode([ir]).write(to: irFile)

        let bridgeDir = workDir.appendingPathComponent("bridges")
        let emitResult = try runProcess(
            executable: cli,
            arguments: ["emit", "--ir", irFile.path, "--out", bridgeDir.path],
            cwd: workDir
        )
        try #require(emitResult.exitCode == 0, "emit failed: \(emitResult.stderr)")

        let outO = workDir.appendingPathComponent("HybridSimpleMath.o")
        let compileResult = try runProcess(
            executable: cli,
            arguments: [
                "compile",
                "--ir", irFile.path,
                "--user-swift", userSwift.path,
                "--bridge-dir", bridgeDir.path,
                "--out-o", outO.path,
                "--arch", "aarch64",
                "--swiftc", swiftc.path,
            ],
            cwd: workDir
        )
        try #require(
            compileResult.exitCode == 0,
            "compile failed:\nstdout: \(compileResult.stdout)\nstderr: \(compileResult.stderr)"
        )
        #expect(FileManager.default.fileExists(atPath: outO.path))
    }

    @Test("rejects unknown flag")
    func cliRejectsUnknownFlag() throws {
        let workspaceRoot = try resolveWorkspaceRoot()
        let cli = workspaceRoot
            .appendingPathComponent("packages/nitrogen-swift-embedded/.build/debug/nitrogen-swift-embedded")
        try #require(FileManager.default.fileExists(atPath: cli.path))

        let result = try runProcess(
            executable: cli,
            arguments: ["emit", "--bogus", "x"],
            cwd: workspaceRoot
        )
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("unknown flag"))
    }

    private func locateSwift63Swiftc() -> URL? {
        let candidates = [
            "~/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin/swiftc",
            "~/Library/Developer/Toolchains/swift-6.3.0-RELEASE.xctoolchain/usr/bin/swiftc",
            "~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc",
        ]
        for raw in candidates {
            let expanded = NSString(string: raw).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }
        return nil
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
