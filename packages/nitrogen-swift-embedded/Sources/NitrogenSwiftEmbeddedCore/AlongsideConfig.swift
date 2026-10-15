import Foundation
import NitrogenSwiftInputCore

/// What the alongside pass needs out of `nitro.json`, resolved and validated.
///
/// Opt-in is the `swiftstitch` block; nitrogen strips unknown top-level keys at
/// parse, so the block is invisible to it. Absent block means the module wants
/// nothing from SwiftStitch on Android. `load` returns `nil` and the pass is a
/// no-op, because iOS-only authors run the same command.
public struct AlongsideConfig: Sendable, Equatable {
    /// The spec name and the implementation class name are *both* read from
    /// `nitro.json` and never derived from one another. By convention the class
    /// is `Hybrid` + spec name, but an author who breaks that convention must
    /// still build.
    public struct Entry: Sendable, Equatable {
        public let specName: String            // "SimpleMath"
        public let className: String           // "HybridSimpleMath"

        public init(specName: String, className: String) {
            self.specName = specName
            self.className = className
        }
    }

    /// `android.androidCxxLibName`, the CMake target the `.o` is added to.
    public let hostLibraryName: String
    /// Fully qualified, e.g. "margelo::nitro::embedded". Distinct from
    /// NitroJSON.cxxNamespace, which is the raw array (["embedded"]).
    public let qualifiedNamespace: String
    /// Where the author's `Hybrid<Name>.swift` files live, relative to the
    /// directory holding `nitro.json`.
    public let userSwiftDir: String
    public let entries: [Entry]

    public init(
        hostLibraryName: String,
        qualifiedNamespace: String,
        userSwiftDir: String,
        entries: [Entry]
    ) {
        self.hostLibraryName = hostLibraryName
        self.qualifiedNamespace = qualifiedNamespace
        self.userSwiftDir = userSwiftDir
        self.entries = entries
    }

    /// Returns nil when there is no `swiftstitch` block. That is a no-op, not an error.
    public static func load(nitroJSONPath: String) throws -> AlongsideConfig? {
        guard let nitroJSON = try NitroJSONReader.load(at: nitroJSONPath) else { return nil }
        guard let block = nitroJSON.swiftstitch else { return nil }

        guard let cxxNamespace = nitroJSON.cxxNamespace else {
            throw AlongsideError.missingField("cxxNamespace")
        }
        guard let hostLibraryName = nitroJSON.android?.androidCxxLibName else {
            throw AlongsideError.missingField("android.androidCxxLibName")
        }

        let entries = try block.swiftOnAndroid.map { specName -> Entry in
            guard let spec = nitroJSON.autolinking?[specName] else {
                throw AlongsideError.unknownSpec(specName)
            }
            // A spec with no `android` block at all lands here too: it declares
            // no Android language, which is equally not "c++".
            let language = spec.android?.language ?? "(none)"
            guard language == Language.cpp.rawValue else {
                throw AlongsideError.androidNotCxx(spec: specName, found: language)
            }
            guard let className = spec.android?.implementationClassName else {
                throw AlongsideError.missingField(
                    "autolinking.\(specName).android.implementationClassName")
            }
            return Entry(specName: specName, className: className)
        }

        return AlongsideConfig(
            hostLibraryName: hostLibraryName,
            qualifiedNamespace: "margelo::nitro::" + cxxNamespace.joined(separator: "::"),
            userSwiftDir: block.userSwiftDir,
            entries: entries
        )
    }
}

public enum AlongsideError: Error, CustomStringConvertible, Equatable {
    case unknownSpec(String)
    case androidNotCxx(spec: String, found: String)
    case missingIR(spec: String, expectedPath: String)
    case missingUserSwift(className: String, expectedPath: String)
    case missingField(String)

    public var description: String {
        switch self {
        case .unknownSpec(let spec):
            return """
            swiftstitch.swiftOnAndroid lists "\(spec)", which has no entry under \
            "autolinking" in nitro.json
            """
        case .androidNotCxx(let spec, let found):
            return """
            spec "\(spec)" declares android language "\(found)"; SwiftStitch \
            requires "c++" (nitrogen rejects "swift")
            """
        case .missingIR(let spec, let expectedPath):
            return """
            no IR for spec "\(spec)" at \(expectedPath). Run `nitrogen-swift-input emit` first.
            """
        case .missingUserSwift(let className, let expectedPath):
            return """
            no Swift implementation for "\(className)" at \(expectedPath)
            """
        case .missingField(let field):
            return "nitro.json is missing \"\(field)\", which SwiftStitch needs"
        }
    }
}
