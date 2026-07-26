import Foundation
import Testing
@testable import NitrogenSwiftInputCore

@Suite("Type coverage — Bool / Double / Float / Int64 / UInt64 / Void")
struct TypesCoverageTests {
    private let iosKotlin: [PlatformBinding] = [
        PlatformBinding(platform: .ios, language: .swift),
        PlatformBinding(platform: .android, language: .kotlin),
    ]

    @Test("HybridTypes fixture extracts all nine methods in source order")
    func extractsAllMethods() throws {
        let url = try fixtureURL("HybridTypes.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let results = try HybridObjectExtractor.extract(
            source: source,
            platforms: iosKotlin,
            fileName: "HybridTypes.swift"
        )
        try #require(results.count == 1)
        let object = results[0]
        #expect(object.className == "HybridTypes")
        #expect(object.specName == "Types")
        #expect(object.platforms == iosKotlin)
        #expect(object.methods.map(\.name) == [
            "passBool",
            "passDouble",
            "passFloat",
            "passInt64",
            "passUInt64",
            "returnsVoid",
            "explicitVoid",
            "throwingAdd",
            "noArgs",
        ])
    }

    @Test(
        "Each in-scope primitive maps as a parameter",
        arguments: [
            ParamCase(swift: "Bool", expected: .bool, ts: "boolean"),
            ParamCase(swift: "Double", expected: .double, ts: "number"),
            ParamCase(swift: "Float", expected: .float, ts: "number"),
            ParamCase(swift: "Int64", expected: .int64, ts: "Int64"),
            ParamCase(swift: "UInt64", expected: .uint64, ts: "UInt64"),
        ]
    )
    func eachPrimitiveAsParameter(_ kase: ParamCase) throws {
        let source = """
        public final class HybridProbe {
            public func probe(value: \(kase.swift)) {}
        }
        """
        let results = try HybridObjectExtractor.extract(source: source, platforms: iosKotlin)
        try #require(results.count == 1)
        let method = results[0].methods[0]
        #expect(method.parameters[0].type == kase.expected)
        let ts = NitroTSEmitter.emit(results)
        #expect(ts.contains("probe(value: \(kase.ts)): void"))
    }

    @Test(
        "Each in-scope primitive maps as a return type",
        arguments: [
            ReturnCase(swift: "Bool", expected: .bool, ts: "boolean"),
            ReturnCase(swift: "Double", expected: .double, ts: "number"),
            ReturnCase(swift: "Float", expected: .float, ts: "number"),
            ReturnCase(swift: "Int64", expected: .int64, ts: "Int64"),
            ReturnCase(swift: "UInt64", expected: .uint64, ts: "UInt64"),
            ReturnCase(swift: "Void", expected: .void, ts: "void"),
        ]
    )
    func eachPrimitiveAsReturn(_ kase: ReturnCase) throws {
        let source = """
        public final class HybridProbe {
            public func probe() -> \(kase.swift) { fatalError() }
        }
        """
        let results = try HybridObjectExtractor.extract(source: source, platforms: iosKotlin)
        try #require(results.count == 1)
        #expect(results[0].methods[0].returnType == kase.expected)
        let ts = NitroTSEmitter.emit(results)
        #expect(ts.contains("probe(): \(kase.ts)"))
    }

    @Test("Implicit and explicit `() ` returns both produce TS `void`")
    func voidVariants() throws {
        let source = """
        public final class HybridProbe {
            public func implicit() {}
            public func explicit() -> () {}
            public func absoluteVoid() -> Void {}
        }
        """
        let results = try HybridObjectExtractor.extract(source: source, platforms: iosKotlin)
        try #require(results[0].methods.count == 3)
        #expect(results[0].methods.allSatisfy { $0.returnType == .void })
        let ts = NitroTSEmitter.emit(results)
        #expect(ts.contains("implicit(): void"))
        #expect(ts.contains("explicit(): void"))
        #expect(ts.contains("absoluteVoid(): void"))
    }

    @Test("`throws` is captured in the IR but does not change the TS surface")
    func throwsDropsFromTS() throws {
        let source = """
        public final class HybridProbe {
            public func plain(a: Double, b: Double) -> Double { a + b }
            public func throwing(a: Double, b: Double) throws -> Double { a + b }
        }
        """
        let results = try HybridObjectExtractor.extract(source: source, platforms: iosKotlin)
        let methods = results[0].methods
        try #require(methods.count == 2)
        #expect(methods[0].isThrowing == false)
        #expect(methods[1].isThrowing == true)

        let ts = NitroTSEmitter.emit(results)
        #expect(ts.contains("plain(a: number, b: number): number"))
        #expect(ts.contains("throwing(a: number, b: number): number"))
        #expect(!ts.contains("throws"))
    }

    @Test("Float-only signature still imports nothing exotic")
    func floatOnlyImports() throws {
        let source = """
        public final class HybridProbe {
            public func probe(value: Float) -> Float { value }
        }
        """
        let results = try HybridObjectExtractor.extract(
            source: source,
            platforms: [PlatformBinding(platform: .ios, language: .swift)]
        )
        let ts = NitroTSEmitter.emit(results)
        #expect(ts.contains("import type { HybridObject } from 'react-native-nitro-modules'"))
        #expect(!ts.contains("Int64"))
        #expect(!ts.contains("UInt64"))
        #expect(ts.contains("probe(value: number): number"))
    }

    @Test("HybridTypes fixture matches its golden file byte-for-byte")
    func hybridTypesGolden() throws {
        let url = try fixtureURL("HybridTypes.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let objects = try HybridObjectExtractor.extract(
            source: source,
            platforms: iosKotlin,
            fileName: "HybridTypes.swift"
        )
        let actual = NitroTSEmitter.emit(objects)
        let goldenURL = try fixtureURL("HybridTypes.nitro.ts.golden")
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
        #expect(actual == golden, "type-matrix golden drift:\n--- expected ---\n\(golden)--- actual ---\n\(actual)")
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

struct ParamCase: Sendable, CustomStringConvertible {
    let swift: String
    let expected: TypeIR
    let ts: String
    var description: String { swift }
}

struct ReturnCase: Sendable, CustomStringConvertible {
    let swift: String
    let expected: TypeIR
    let ts: String
    var description: String { swift }
}
