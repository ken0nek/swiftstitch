import Foundation
import Testing
@testable import NitrogenSwiftInputCore

@Suite("Phase 1G.1 — IR JSON codec")
struct IRJSONCodecTests {
    private let bothSwift: [PlatformBinding] = [
        PlatformBinding(platform: .ios, language: .swift),
        PlatformBinding(platform: .android, language: .swift),
    ]

    @Test("HybridMath fixture round-trips through extractor + encoder to golden JSON")
    func hybridMathGolden() throws {
        let url = try fixtureURL("HybridMath.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let objects = try HybridObjectExtractor.extract(
            source: source,
            platforms: bothSwift,
            fileName: "HybridMath.swift"
        )
        let encoded = try IRJSONCodec.encode(objects)
        let actual = String(data: encoded, encoding: .utf8) ?? ""

        let goldenURL = try fixtureURL("HybridMath.ir.json.golden")
        let goldenWithTrailingNewline = try String(contentsOf: goldenURL, encoding: .utf8)
        let golden = goldenWithTrailingNewline.trimmingCharacters(in: .newlines)
        #expect(actual == golden, "IR JSON drift:\n--- expected ---\n\(golden)\n--- actual ---\n\(actual)")
    }

    @Test("Round-trip: encode then decode yields the original IR")
    func roundTrip() throws {
        let original = HybridObjectIR(
            className: "HybridFoo",
            platforms: [
                PlatformBinding(platform: .ios, language: .swift),
                PlatformBinding(platform: .android, language: .kotlin),
            ],
            methods: [
                MethodIR(
                    name: "noop",
                    parameters: [],
                    returnType: .void,
                    isThrowing: false
                ),
                MethodIR(
                    name: "compute",
                    parameters: [
                        ParameterIR(label: "x", type: .double),
                        ParameterIR(label: "n", type: .int64),
                        ParameterIR(label: "active", type: .bool),
                    ],
                    returnType: .uint64,
                    isThrowing: true
                ),
            ]
        )
        let data = try IRJSONCodec.encode([original])
        let decoded = try IRJSONCodec.decode(data)
        try #require(decoded.count == 1)
        // sourceLocation is intentionally omitted from the wire format — it
        // would force the receiver to handle an optional that adds no value.
        #expect(decoded[0].className == original.className)
        #expect(decoded[0].platforms == original.platforms)
        #expect(decoded[0].methods == original.methods)
    }

    @Test("Decoder rejects unknown schema version")
    func rejectsUnknownSchemaVersion() throws {
        let json = #"""
        {"schemaVersion": 99, "objects": []}
        """#
        let data = json.data(using: .utf8)!
        #expect(throws: Diagnostic.self) {
            try IRJSONCodec.decode(data)
        }
    }

    @Test("Decoder rejects unknown type kind")
    func rejectsUnknownTypeKind() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "objects": [{
            "className": "HybridFoo",
            "specName": "Foo",
            "platforms": [{"platform": "ios", "language": "swift"}],
            "methods": [{
              "name": "weird",
              "parameters": [],
              "returnType": {"kind": "string"},
              "isThrowing": false
            }]
          }]
        }
        """#
        let data = json.data(using: .utf8)!
        #expect(throws: Diagnostic.self) {
            try IRJSONCodec.decode(data)
        }
    }

    @Test("Decoder rejects unknown platform / language")
    func rejectsUnknownPlatform() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "objects": [{
            "className": "HybridFoo",
            "specName": "Foo",
            "platforms": [{"platform": "web", "language": "swift"}],
            "methods": []
          }]
        }
        """#
        let data = json.data(using: .utf8)!
        #expect(throws: Diagnostic.self) {
            try IRJSONCodec.decode(data)
        }
    }

    @Test("Empty objects array round-trips")
    func emptyObjects() throws {
        let data = try IRJSONCodec.encode([])
        let decoded = try IRJSONCodec.decode(data)
        #expect(decoded.isEmpty)
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
