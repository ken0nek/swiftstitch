import Foundation
import Testing
@testable import NitrogenSwiftInputCore

@Suite(".nitro.ts emitter")
struct NitroTSEmitterTests {
    private let bothSwift: [PlatformBinding] = [
        PlatformBinding(platform: .ios, language: .swift),
        PlatformBinding(platform: .android, language: .swift),
    ]

    @Test("HybridMath fixture round-trips through extractor and emitter to golden")
    func hybridMathGolden() throws {
        let url = try fixtureURL("HybridMath.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let objects = try HybridObjectExtractor.extract(
            source: source,
            platforms: bothSwift,
            fileName: "HybridMath.swift"
        )
        let actual = NitroTSEmitter.emit(objects)

        let goldenURL = try fixtureURL("HybridMath.nitro.ts.golden")
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
        #expect(actual == golden, "Emitter output drifted from golden file:\n--- expected ---\n\(golden)--- actual ---\n\(actual)")
    }

    @Test("Imports drop Int64/UInt64 when only number/boolean/void are used")
    func minimalImports() throws {
        let object = HybridObjectIR(
            className: "HybridFoo",
            platforms: [PlatformBinding(platform: .ios, language: .swift)],
            methods: [
                MethodIR(
                    name: "trigger",
                    parameters: [ParameterIR(label: "enabled", type: .bool)],
                    returnType: .void,
                    isThrowing: false
                )
            ]
        )
        let actual = NitroTSEmitter.emit([object])
        #expect(actual.contains("import type { HybridObject } from 'react-native-nitro-modules'"))
        #expect(!actual.contains("Int64"))
        #expect(!actual.contains("UInt64"))
    }

    @Test("Multiple HybridObjects are separated by a blank line")
    func multipleObjectsSpacing() throws {
        let a = HybridObjectIR(
            className: "HybridA",
            platforms: [PlatformBinding(platform: .ios, language: .swift)],
            methods: [
                MethodIR(name: "ping", parameters: [], returnType: .void, isThrowing: false)
            ]
        )
        let b = HybridObjectIR(
            className: "HybridB",
            platforms: [PlatformBinding(platform: .android, language: .kotlin)],
            methods: [
                MethodIR(name: "pong", parameters: [], returnType: .void, isThrowing: false)
            ]
        )
        let actual = NitroTSEmitter.emit([a, b])
        let expectedFragment = """
        export interface A extends HybridObject<{ ios: 'swift' }> {
          ping(): void
        }

        export interface B extends HybridObject<{ android: 'kotlin' }> {
          pong(): void
        }
        """
        #expect(actual.contains(expectedFragment))
    }

    @Test("Platform spec keys preserved in canonical ios → android order")
    func platformOrder() throws {
        let object = HybridObjectIR(
            className: "HybridFoo",
            platforms: [
                PlatformBinding(platform: .android, language: .swift),
                PlatformBinding(platform: .ios, language: .swift),
            ],
            methods: []
        )
        let actual = NitroTSEmitter.emit([object])
        #expect(actual.contains("HybridObject<{ ios: 'swift'; android: 'swift' }>"))
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
