import Foundation
import Testing
@testable import NitrogenSwiftInputCore

@Suite("Method signature extraction")
struct MethodExtractorTests {
    private let platforms: [PlatformBinding] = [
        PlatformBinding(platform: .ios, language: .swift),
        PlatformBinding(platform: .android, language: .swift),
    ]

    @Test("HybridMath fixture: extracts add/subtract/magnitude/reset")
    func hybridMathMethods() throws {
        let url = try fixtureURL("HybridMath.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let results = try HybridObjectExtractor.extract(
            source: source,
            platforms: platforms,
            fileName: "HybridMath.swift"
        )
        try #require(results.count == 1)
        let math = results[0]
        try #require(math.methods.count == 4)

        let add = math.methods[0]
        #expect(add.name == "add")
        #expect(add.parameters == [
            ParameterIR(label: "a", type: .double),
            ParameterIR(label: "b", type: .double),
        ])
        #expect(add.returnType == .double)
        #expect(add.isThrowing)

        let subtract = math.methods[1]
        #expect(subtract.name == "subtract")
        #expect(subtract.parameters == [
            ParameterIR(label: "a", type: .int64),
            ParameterIR(label: "b", type: .int64),
        ])
        #expect(subtract.returnType == .int64)
        #expect(!subtract.isThrowing)

        let magnitude = math.methods[2]
        #expect(magnitude.name == "magnitude")
        #expect(magnitude.parameters == [
            ParameterIR(label: "value", type: .int64),
        ])
        #expect(magnitude.returnType == .uint64)

        let reset = math.methods[3]
        #expect(reset.name == "reset")
        #expect(reset.parameters.isEmpty)
        #expect(reset.returnType == .void)
        #expect(!reset.isThrowing)
    }

    @Test("Skips non-public methods")
    func skipsNonPublic() throws {
        let source = """
        public final class HybridFoo {
            public func keepMe() -> Int64 { 0 }
            internal func dropMe() -> Int64 { 0 }
            private func dropMeToo() -> Int64 { 0 }
            func packageDefaultDrops() -> Int64 { 0 }
        }
        """
        let results = try HybridObjectExtractor.extract(source: source, platforms: platforms)
        try #require(results.count == 1)
        #expect(results[0].methods.map(\.name) == ["keepMe"])
    }

    @Test("Underscored external label uses the internal name")
    func underscoredLabel() throws {
        let source = """
        public final class HybridFoo {
            public func double(_ value: Double) -> Double { value * 2 }
        }
        """
        let results = try HybridObjectExtractor.extract(source: source, platforms: platforms)
        try #require(results.count == 1)
        let m = results[0].methods[0]
        #expect(m.parameters == [ParameterIR(label: "value", type: .double)])
    }

    @Test("Bool params and return are accepted")
    func boolType() throws {
        let source = """
        public final class HybridFoo {
            public func toggle(value: Bool) -> Bool { !value }
        }
        """
        let results = try HybridObjectExtractor.extract(source: source, platforms: platforms)
        let m = results[0].methods[0]
        #expect(m.parameters == [ParameterIR(label: "value", type: .bool)])
        #expect(m.returnType == .bool)
    }

    @Test("Empty tuple `()` return is treated as Void")
    func emptyTupleReturn() throws {
        let source = """
        public final class HybridFoo {
            public func noop() -> () {}
        }
        """
        let results = try HybridObjectExtractor.extract(source: source, platforms: platforms)
        #expect(results[0].methods[0].returnType == .void)
    }

    @Test("String parameter rejected with diagnostic")
    func rejectsString() throws {
        let source = """
        public final class HybridFoo {
            public func greet(name: String) -> String { name }
        }
        """
        #expect(throws: Diagnostic.self) {
            try HybridObjectExtractor.extract(source: source, platforms: platforms)
        }
    }

    @Test("Array return rejected with diagnostic")
    func rejectsArray() throws {
        let source = """
        public final class HybridFoo {
            public func numbers() -> [Double] { [] }
        }
        """
        #expect(throws: Diagnostic.self) {
            try HybridObjectExtractor.extract(source: source, platforms: platforms)
        }
    }

    @Test("Optional rejected with diagnostic")
    func rejectsOptional() throws {
        let source = """
        public final class HybridFoo {
            public func maybe() -> Double? { nil }
        }
        """
        #expect(throws: Diagnostic.self) {
            try HybridObjectExtractor.extract(source: source, platforms: platforms)
        }
    }

    @Test("Plain `Int` rejected — scope is fixed-width Int64/UInt64")
    func rejectsBareInt() throws {
        let source = """
        public final class HybridFoo {
            public func count() -> Int { 0 }
        }
        """
        #expect(throws: Diagnostic.self) {
            try HybridObjectExtractor.extract(source: source, platforms: platforms)
        }
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return url
    }

    private enum FixtureError: Error {
        case missing(String)
    }
}
