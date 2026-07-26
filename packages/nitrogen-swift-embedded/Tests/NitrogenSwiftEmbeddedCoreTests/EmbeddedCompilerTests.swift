import Foundation
import Testing
@testable import NitrogenSwiftEmbeddedCore
@testable import NitrogenSwiftInputCore

/// These tests need a Swift 6.3+ toolchain on disk because Embedded Swift +
/// `@c` shipped in 6.3. If `~/Library/Developer/Toolchains/swift-6.3.x...` is
/// missing the test is skipped — the spike is reproducible but only in
/// environments that have done `swiftly install 6.3.1`.
private func locateSwift63Toolchain() -> URL? {
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

@Suite("EmbeddedCompiler")
struct EmbeddedCompilerTests {
    @Test("compiles a HybridSimpleMath fixture to aarch64 elf object")
    func compilesToObject() throws {
        guard let swiftc = locateSwift63Toolchain() else {
            Issue.record("Swift 6.3+ toolchain not installed; skipping")
            return
        }

        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("embedded-compile-\(UUID().uuidString)")
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
        let bridgeText = try CBridgeEmitter.emit(ir)
        let bridgeFile = workDir.appendingPathComponent("HybridSimpleMath+CBridge.swift")
        try bridgeText.write(to: bridgeFile, atomically: true, encoding: .utf8)

        let outO = workDir.appendingPathComponent("HybridSimpleMath.o")
        let compiler = EmbeddedCompiler()
        try compiler.compile(EmbeddedCompiler.Inputs(
            userSwiftFiles: [userSwift],
            bridgeSwiftFiles: [bridgeFile],
            outputObjectFile: outO,
            architecture: .aarch64,
            swiftcPath: swiftc
        ))

        #expect(FileManager.default.fileExists(atPath: outO.path))
        // Sanity: object file should be > 1KB (Embedded artifact).
        let attrs = try FileManager.default.attributesOfItem(atPath: outO.path)
        let size = attrs[.size] as? Int ?? 0
        #expect(size > 1024, "object file unexpectedly small: \(size) bytes")
    }

    @Test("rejects missing swiftc")
    func rejectsMissingSwiftc() throws {
        let bogus = URL(fileURLWithPath: "/nonexistent/swiftc")
        let inputs = EmbeddedCompiler.Inputs(
            userSwiftFiles: [URL(fileURLWithPath: "/dev/null")],
            bridgeSwiftFiles: [],
            outputObjectFile: URL(fileURLWithPath: "/tmp/out.o"),
            architecture: .aarch64,
            swiftcPath: bogus
        )
        #expect(throws: EmbeddedCompiler.CompilerError.self) {
            try EmbeddedCompiler().compile(inputs)
        }
    }
}
