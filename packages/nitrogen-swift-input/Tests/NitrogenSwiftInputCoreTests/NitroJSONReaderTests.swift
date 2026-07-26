import Foundation
import Testing
@testable import NitrogenSwiftInputCore

@Suite("nitro.json reader")
struct NitroJSONReaderTests {
    @Test("Missing file returns nil (caller decides whether that's an error)")
    func missingFileReturnsNil() throws {
        let path = uniqueTempPath(suffix: "missing-nitro.json")
        let result = try NitroJSONReader.load(at: path)
        #expect(result == nil)
    }

    @Test("Valid file with one spec decodes ios + android language")
    func bothPlatformsDecoded() throws {
        let path = try writeTempJSON("""
        {
          "autolinking": {
            "Counter": {
              "ios": { "language": "swift", "implementationClassName": "HybridCounter" },
              "android": { "language": "kotlin", "implementationClassName": "HybridCounter" }
            }
          }
        }
        """)
        let json = try NitroJSONReader.load(at: path)
        let platforms = NitroJSONReader.platforms(for: "Counter", in: json)
        #expect(platforms == [
            PlatformBinding(platform: .ios, language: .swift),
            PlatformBinding(platform: .android, language: .kotlin),
        ])
    }

    @Test("iOS-only spec yields only the ios binding")
    func iOSOnlySpec() throws {
        let path = try writeTempJSON("""
        {
          "autolinking": {
            "OnlyIOS": {
              "ios": { "language": "swift" }
            }
          }
        }
        """)
        let json = try NitroJSONReader.load(at: path)
        let platforms = NitroJSONReader.platforms(for: "OnlyIOS", in: json)
        #expect(platforms == [PlatformBinding(platform: .ios, language: .swift)])
    }

    @Test("Spec missing from autolinking yields empty platforms")
    func unknownSpec() throws {
        let path = try writeTempJSON(#"{ "autolinking": {} }"#)
        let json = try NitroJSONReader.load(at: path)
        #expect(NitroJSONReader.platforms(for: "Counter", in: json).isEmpty)
    }

    @Test("Nil nitro.json yields empty platforms (no crash on lookups)")
    func nilJSON() {
        #expect(NitroJSONReader.platforms(for: "Counter", in: nil).isEmpty)
    }

    @Test("Unknown language string is skipped (decoder is forward-compatible)")
    func unknownLanguageSkipped() throws {
        // Forward-compat: if nitro.json names a language we don't model yet
        // (e.g. some hypothetical "rust"), don't crash — just drop the binding.
        // The CLI will then complain about empty platforms, which is the right
        // surface for the user.
        let path = try writeTempJSON("""
        {
          "autolinking": {
            "X": {
              "ios": { "language": "rust" }
            }
          }
        }
        """)
        let json = try NitroJSONReader.load(at: path)
        #expect(NitroJSONReader.platforms(for: "X", in: json).isEmpty)
    }

    @Test("Malformed JSON throws a typed error")
    func malformedJSON() throws {
        let path = try writeTempJSON("not-json")
        #expect(throws: NitroJSONError.self) {
            _ = try NitroJSONReader.load(at: path)
        }
    }

    // MARK: - Helpers

    private func uniqueTempPath(suffix: String) -> String {
        let dir = NSTemporaryDirectory()
        return (dir as NSString).appendingPathComponent("nsi-\(UUID().uuidString)-\(suffix)")
    }

    private func writeTempJSON(_ body: String) throws -> String {
        let path = uniqueTempPath(suffix: "nitro.json")
        try body.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
