import Foundation
import Testing
@testable import NitrogenSwiftEmbeddedCore
@testable import NitrogenSwiftInputCore

/// End-to-end: emitter → swiftc (Embedded) → NDK clang link → Android `.so`.
///
/// Verifies the Embedded pipeline actually produces a single-`.so` Android
/// artifact with no per-Hybrid Swift `.so` and no Swift stdlib in jniLibs.
@Suite("End-to-end: Swift → .o → Android .so")
struct EndToEndIntegrationTests {
    @Test(
        "HybridSimpleMath: full pipeline produces a single .so with @c symbols and only bionic deps",
        .enabled(if: ToolchainAvailability.hasSwift63 && ToolchainAvailability.hasAndroidNDK)
    )
    func fullPipeline() throws {
        let swiftc = locateSwift63Swiftc()!
        let ndkClang = locateAndroidClang()!

        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nse-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // 1. User Swift class.
        let userSwift = workDir.appendingPathComponent("HybridSimpleMath.swift")
        try """
        public final class HybridSimpleMath {
            public init() {}
            public func add(a: Double, b: Double) -> Double { a + b }
            public func subtract(a: Int64, b: Int64) -> Int64 { a - b }
        }
        """.write(to: userSwift, atomically: true, encoding: .utf8)

        // 2. Build IR (skip the parser; tests for that live in nitrogen-swift-input).
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

        // 3. Emit the @c bridge .swift.
        let bridgeText = try CBridgeEmitter.emit(ir)
        let bridgeFile = workDir.appendingPathComponent("HybridSimpleMath+CBridge.swift")
        try bridgeText.write(to: bridgeFile, atomically: true, encoding: .utf8)

        // 4. Embedded swiftc → .o
        let swiftO = workDir.appendingPathComponent("HybridSimpleMath.o")
        try EmbeddedCompiler().compile(EmbeddedCompiler.Inputs(
            userSwiftFiles: [userSwift],
            bridgeSwiftFiles: [bridgeFile],
            outputObjectFile: swiftO,
            architecture: .aarch64,
            swiftcPath: swiftc
        ))

        // 5. Stub HybridSimpleMathSpec.hpp so the C++ glue header has something
        // to inherit from. In production this comes from nitrogen.
        let specHpp = workDir.appendingPathComponent("HybridSimpleMathSpec.hpp")
        try """
        #pragma once
        #include <cstdint>
        namespace margelo::nitro::test {
        class HybridObject {
        public:
          explicit HybridObject(const char*) {}
          virtual ~HybridObject() = default;
        };
        class HybridSimpleMathSpec : public virtual HybridObject {
        public:
          HybridSimpleMathSpec(): HybridObject(TAG) {}
          ~HybridSimpleMathSpec() override = default;
          virtual double add(double a, double b) = 0;
          virtual int64_t subtract(int64_t a, int64_t b) = 0;
        protected:
          static constexpr auto TAG = "SimpleMath";
        };
        }
        """.write(to: specHpp, atomically: true, encoding: .utf8)

        // 6. Generate the C++ glue header.
        let glueText = try CppGlueEmitter.emit(ir, namespace: "margelo::nitro::test")
        let glueHpp = workDir.appendingPathComponent("HybridSimpleMath.hpp")
        try glueText.write(to: glueHpp, atomically: true, encoding: .utf8)

        // 7. A tiny C++ host that uses the glue class.
        let hostCpp = workDir.appendingPathComponent("host.cpp")
        try """
        #include "HybridSimpleMath.hpp"
        using namespace margelo::nitro::test;

        extern "C" __attribute__((visibility("default")))
        double NitroTest_add(double a, double b) {
            HybridSimpleMath m;
            return m.add(a, b);
        }
        extern "C" __attribute__((visibility("default")))
        int64_t NitroTest_subtract(int64_t a, int64_t b) {
            HybridSimpleMath m;
            return m.subtract(a, b);
        }
        """.write(to: hostCpp, atomically: true, encoding: .utf8)

        // 8. NDK link: C++ host + Swift .o → Android .so.
        let outSo = workDir.appendingPathComponent("libNitroTestEmbedded.so")
        let linkResult = try runProcess(
            executable: ndkClang,
            arguments: [
                "-shared", "-fPIC", "-O2",
                "-I", workDir.path,
                "-o", outSo.path,
                hostCpp.path, swiftO.path,
            ],
            cwd: workDir
        )
        try #require(
            linkResult.exitCode == 0,
            "NDK link failed:\nstdout: \(linkResult.stdout)\nstderr: \(linkResult.stderr)"
        )
        #expect(FileManager.default.fileExists(atPath: outSo.path))

        // 9. Verify the .so has exactly the expected dynamic deps — bionic only,
        // NO libswiftCore.so / libFoundation*.so. This is the headline assertion
        // of this package: no Swift runtime in jniLibs.
        let needed = try dynamicNeededLibs(of: outSo, ndkRoot: try ndkRoot())
        #expect(!needed.contains { $0.lowercased().contains("swift") },
                "unexpected Swift runtime dependency: \(needed)")
        #expect(!needed.contains { $0.lowercased().contains("foundation") },
                "unexpected Foundation dependency: \(needed)")
        // Sanity: bionic libc must be present.
        #expect(needed.contains { $0.contains("libc.so") })

        // 10. Verify the @c symbols are present in the linked .so.
        let symbols = try dynamicSymbols(of: outSo, ndkRoot: try ndkRoot())
        for required in [
            "HybridSimpleMath_create",
            "HybridSimpleMath_destroy",
            "HybridSimpleMath_add",
            "HybridSimpleMath_subtract",
            "NitroTest_add",
            "NitroTest_subtract",
        ] {
            #expect(symbols.contains(required), "missing symbol \(required)")
        }
    }

    // MARK: - Toolchain probes
    //
    // `locateSwift63Swiftc()`, `locateAndroidClang()`, and `ndkRoot()` live in
    // ToolchainAvailability.swift as shared internal free functions.

    private func dynamicNeededLibs(of soURL: URL, ndkRoot: URL) throws -> [String] {
        let readelf = try llvmTool("llvm-readelf", ndkRoot: ndkRoot)
        let result = try runProcess(executable: readelf, arguments: ["-d", soURL.path], cwd: soURL.deletingLastPathComponent())
        return result.stdout
            .split(separator: "\n")
            .filter { $0.contains("(NEEDED)") }
            .compactMap { line -> String? in
                guard let openIdx = line.firstIndex(of: "[") else { return nil }
                guard let closeIdx = line.firstIndex(of: "]") else { return nil }
                let after = line.index(after: openIdx)
                if after >= closeIdx { return nil }
                return String(line[after..<closeIdx])
            }
    }

    private func dynamicSymbols(of soURL: URL, ndkRoot: URL) throws -> Set<String> {
        let nm = try llvmTool("llvm-nm", ndkRoot: ndkRoot)
        let result = try runProcess(executable: nm, arguments: ["-D", "--defined-only", soURL.path], cwd: soURL.deletingLastPathComponent())
        let symbols = result.stdout
            .split(separator: "\n")
            .compactMap { line -> String? in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                return parts.last.map(String.init)
            }
        return Set(symbols)
    }

    private func llvmTool(_ name: String, ndkRoot: URL) throws -> URL {
        let prebuilt = ndkRoot.appendingPathComponent("toolchains/llvm/prebuilt")
        let archDirs = try FileManager.default.contentsOfDirectory(atPath: prebuilt.path)
        for arch in archDirs {
            let bin = prebuilt.appendingPathComponent(arch).appendingPathComponent("bin")
            let candidate = bin.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        struct NoTool: Error, CustomStringConvertible {
            let name: String
            var description: String { "llvm tool \(name) not found in NDK" }
        }
        throw NoTool(name: name)
    }
}
