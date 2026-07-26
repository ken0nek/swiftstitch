import Foundation
import Testing
@testable import NitrogenSwiftInputCore

@Suite("HybridObject class extraction (prefix convention)")
struct HybridObjectExtractorTests {
    private let bothPlatforms: [PlatformBinding] = [
        PlatformBinding(platform: .ios, language: .swift),
        PlatformBinding(platform: .android, language: .swift),
    ]

    @Test("HybridMath fixture returns one IR with the supplied platforms")
    func hybridMathFixture() throws {
        let url = try fixtureURL("HybridMath.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let results = try HybridObjectExtractor.extract(
            source: source,
            platforms: bothPlatforms,
            fileName: "HybridMath.swift"
        )
        try #require(results.count == 1)
        let math = results[0]
        #expect(math.className == "HybridMath")
        #expect(math.specName == "Math")
        #expect(math.platforms == bothPlatforms)
        #expect(math.sourceLocation?.file == "HybridMath.swift")
    }

    @Test("Classes without the `Hybrid` prefix are ignored")
    func skipsNonHybridClasses() throws {
        let source = """
        public final class JustAClass {
            public func add(a: Double, b: Double) -> Double { a + b }
        }
        public final class HybridFoo {
            public func ping() {}
        }
        public final class Hybrid {
            // Bare `Hybrid` doesn't qualify — no spec name to derive.
            public func ping() {}
        }
        """
        let results = try HybridObjectExtractor.extract(
            source: source,
            platforms: [PlatformBinding(platform: .ios, language: .swift)]
        )
        try #require(results.count == 1)
        #expect(results[0].className == "HybridFoo")
    }

    @Test("Multiple `Hybrid<X>` classes in one file all surface")
    func multipleClasses() throws {
        let source = """
        public final class HybridA {
            public func ping() {}
        }
        public final class HybridB {
            public func pong() {}
        }
        """
        let results = try HybridObjectExtractor.extract(
            source: source,
            platforms: bothPlatforms
        )
        try #require(results.count == 2)
        #expect(results.map(\.className) == ["HybridA", "HybridB"])
        #expect(results.allSatisfy { $0.platforms == bothPlatforms })
    }

    @Test("Empty platforms list passes through to the IR (CLI re-stamps later)")
    func emptyPlatformsPassThrough() throws {
        let source = """
        public final class HybridFoo {
            public func ping() {}
        }
        """
        let results = try HybridObjectExtractor.extract(source: source, platforms: [])
        try #require(results.count == 1)
        #expect(results[0].platforms.isEmpty)
    }

    @Test("Source with no Hybrid* classes returns empty")
    func noHybridClassesReturnsEmpty() throws {
        let source = """
        public final class Foo {}
        public final class Bar {}
        """
        let results = try HybridObjectExtractor.extract(
            source: source,
            platforms: [PlatformBinding(platform: .ios, language: .swift)]
        )
        #expect(results.isEmpty)
    }

    @Test("Stray `@HybridObject` attribute is tolerated (parser sees it as unknown attr)")
    func toleratesStrayAttribute() throws {
        // We've dropped the attribute requirement, but a user still mid-migration
        // might leave one in place. swift-syntax accepts unknown attributes.
        let source = """
        @HybridObject(ios: .swift, android: .swift)
        public final class HybridFoo {
            public func ping() {}
        }
        """
        let results = try HybridObjectExtractor.extract(
            source: source,
            platforms: bothPlatforms
        )
        try #require(results.count == 1)
        #expect(results[0].className == "HybridFoo")
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
