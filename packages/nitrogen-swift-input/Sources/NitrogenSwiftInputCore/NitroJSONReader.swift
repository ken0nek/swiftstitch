import Foundation

/// Reads platform bindings from a `nitro.json` file.
///
/// Nitro projects already declare per-spec platform languages under
/// `autolinking.<SpecName>.{ios,android}.language`. Re-typing the same values
/// on the `nitrogen-swift-input emit` invocation is friction, so the CLI
/// reads them from `nitro.json` when its own `--ios` / `--android` flags
/// are unset. Authoritative schema:
/// <https://nitro.margelo.com/nitro.schema.json>.
///
/// Missing file is OK (returns `nil`). A malformed file is a hard error —
/// silently falling back would mask real misconfiguration.
public enum NitroJSONReader {
    public static func load(at path: String) throws -> NitroJSON? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw NitroJSONError.readFailed(path: path, underlying: "\(error)")
        }
        do {
            return try JSONDecoder().decode(NitroJSON.self, from: data)
        } catch {
            throw NitroJSONError.decodeFailed(path: path, underlying: "\(error)")
        }
    }

    /// Look up the iOS / Android language for a given spec name, returning
    /// only the platforms `nitro.json` actually declares (a spec may opt
    /// out of one platform).
    public static func platforms(for specName: String, in nitroJSON: NitroJSON?) -> [PlatformBinding] {
        guard let entry = nitroJSON?.autolinking?[specName] else { return [] }
        var result: [PlatformBinding] = []
        if let raw = entry.ios?.language, let language = Language(rawValue: raw) {
            result.append(PlatformBinding(platform: .ios, language: language))
        }
        if let raw = entry.android?.language, let language = Language(rawValue: raw) {
            result.append(PlatformBinding(platform: .android, language: language))
        }
        return result
    }
}

public struct NitroJSON: Decodable, Sendable, Equatable {
    public let cxxNamespace: [String]?
    public let android: AndroidConfig?
    public let autolinking: [String: Autolinking]?
    public let swiftstitch: SwiftStitchConfig?

    public struct AndroidConfig: Decodable, Sendable, Equatable {
        public let androidCxxLibName: String?
    }

    public struct Autolinking: Decodable, Sendable, Equatable {
        public let ios: PlatformDecl?
        public let android: PlatformDecl?
    }

    public struct PlatformDecl: Decodable, Sendable, Equatable {
        public let language: String?
        public let implementationClassName: String?
    }

    /// Read by SwiftStitch, ignored by nitrogen (which strips unknown
    /// top-level keys at parse). See the plugin's alongside pass.
    public struct SwiftStitchConfig: Decodable, Sendable, Equatable {
        public let userSwiftDir: String
        public let swiftOnAndroid: [String]
    }
}

public enum NitroJSONError: Error, CustomStringConvertible, Equatable {
    case readFailed(path: String, underlying: String)
    case decodeFailed(path: String, underlying: String)

    public var description: String {
        switch self {
        case .readFailed(let path, let underlying):
            return "could not read \(path): \(underlying)"
        case .decodeFailed(let path, let underlying):
            return "\(path) is not valid nitro.json: \(underlying)"
        }
    }
}
