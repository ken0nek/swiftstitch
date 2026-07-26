import Foundation
import Testing
@testable import NitrogenSwiftInputCore

@Suite("Phase 1A.1 — swift-syntax smoke parse")
struct SmokeParseTests {
    @Test("Parser accepts a valid Swift declaration")
    func validSourceHasNoErrors() throws {
        let source = """
        public final class Foo {
            public func bar() -> Int { return 0 }
        }
        """
        #expect(!SmokeParse.hasSyntaxErrors(source))
        #expect(SmokeParse.topLevelDeclCount(source) == 1)
    }

    @Test("Parser flags broken Swift sources")
    func invalidSourceReportsError() throws {
        let source = "public final class Foo { public func bar( -> Int { return 0 } }"
        #expect(SmokeParse.hasSyntaxErrors(source))
    }

    @Test("HybridMath fixture parses without errors")
    func hybridMathFixtureParses() throws {
        let url = try fixtureURL("HybridMath.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!SmokeParse.hasSyntaxErrors(source))
        // One top-level declaration: `@HybridObject ... public final class HybridMath { ... }`.
        #expect(SmokeParse.topLevelDeclCount(source) == 1)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return url
    }
}

private enum FixtureError: Error {
    case missing(String)
}
