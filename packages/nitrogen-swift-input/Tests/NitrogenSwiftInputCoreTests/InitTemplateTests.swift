import Foundation
import Testing
@testable import NitrogenSwiftInputCore

@Suite("Init template")
struct InitTemplateTests {
    @Test("normalize accepts a bare spec name")
    func acceptsBareName() throws {
        #expect(try InitTemplate.normalize(rawName: "Counter") == "Counter")
    }

    @Test("normalize strips a leading Hybrid prefix")
    func stripsHybridPrefix() throws {
        #expect(try InitTemplate.normalize(rawName: "HybridCounter") == "Counter")
    }

    @Test("normalize trims surrounding whitespace")
    func trimsWhitespace() throws {
        #expect(try InitTemplate.normalize(rawName: "  Counter\n") == "Counter")
    }

    @Test("normalize accepts identifiers containing digits and underscores")
    func acceptsAlphanumIdentifier() throws {
        #expect(try InitTemplate.normalize(rawName: "Math_V2") == "Math_V2")
    }

    @Test("normalize rejects empty names")
    func rejectsEmpty() {
        #expect(throws: InitTemplateError.invalidName("")) {
            try InitTemplate.normalize(rawName: "")
        }
    }

    @Test("normalize rejects 'Hybrid' alone (no spec name to derive)")
    func rejectsHybridAlone() {
        #expect(throws: InitTemplateError.invalidName("Hybrid")) {
            try InitTemplate.normalize(rawName: "Hybrid")
        }
    }

    @Test("normalize rejects names starting with a digit")
    func rejectsLeadingDigit() {
        #expect(throws: InitTemplateError.invalidName("1Counter")) {
            try InitTemplate.normalize(rawName: "1Counter")
        }
    }

    @Test("normalize rejects non-identifier characters")
    func rejectsBadChars() {
        #expect(throws: InitTemplateError.invalidName("Counter-X")) {
            try InitTemplate.normalize(rawName: "Counter-X")
        }
    }

    @Test("rendered template substitutes the spec name throughout")
    func templateSubstitution() {
        let body = InitTemplate.render(specName: "Counter")
        #expect(body.contains("public final class HybridCounter: HybridCounterSpec"))
        #expect(body.contains("`Counter.nitro.ts`"))
        #expect(body.contains("`Counter.ir.json`"))
        #expect(body.contains("nitrogen-swift-input init Counter"))
        #expect(body.contains("#if canImport(NitroModules)"))
        #expect(body.contains("import NitroModules"))
        #expect(body.contains("public override init() { super.init() }"))
        #expect(body.hasSuffix("\n"))
    }

    @Test("rendered template round-trips through HybridObjectExtractor")
    func templateParses() throws {
        // The output is the canonical starter file. Round-trip it through
        // the extractor to ensure `nitrogen-swift-input emit` can parse what
        // `init` writes (including the `#if canImport(NitroModules)` wrap).
        let body = InitTemplate.render(specName: "Counter")
        let objects = try HybridObjectExtractor.extract(
            source: body,
            platforms: [PlatformBinding(platform: .ios, language: .swift)],
            fileName: "HybridCounter.swift"
        )
        #expect(objects.count == 1)
        #expect(objects[0].className == "HybridCounter")
        #expect(objects[0].specName == "Counter")
        // No public methods in the template — only commented examples.
        #expect(objects[0].methods.isEmpty)
    }
}
