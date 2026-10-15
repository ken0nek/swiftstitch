import Foundation
import NitrogenSwiftInputCore

/// The post-`bunx nitrogen` pass.
///
/// When a spec declares `android: 'c++'`, nitrogen emits the shared C++ layer
/// and an `#include "Hybrid<Foo>.hpp"` in `<Lib>OnLoad.cpp`, then deliberately
/// leaves the implementation to the author. This pass writes exactly that
/// missing piece, which is the Swift `@c` bridge, the C++ glue header, and the
/// CMake recipe that compiles the Swift. The author writes only
/// `Hybrid<Foo>.swift`.
///
/// It **only ever creates** files, at the three contracted paths under
/// `outDir`, which is `<moduleDir>/swiftstitch/generated/`, our own tree. It never
/// reads or writes anything under `nitrogen/generated/`, which is what keeps
/// the output alive: nitrogen's cleanup snapshots *its* output directory
/// recursively and deletes every file it did not itself generate, so anything
/// of ours placed in there would not survive a bare `bunx nitrogen`.
public enum AlongsideRunner {
    /// Emits the three files for every spec listed in `swiftstitch.swiftOnAndroid`
    /// and returns the paths written, in emission order. Empty means the module
    /// has no `swiftstitch` block. That is a no-op, not an error.
    ///
    /// - Parameters:
    ///   - nitroJSONPath: the module's `nitro.json`; `userSwiftDir` resolves
    ///     against its directory.
    ///   - outDir: where the three files go. It is `<moduleDir>/swiftstitch/generated`
    ///     by convention, which is what the CLI defaults to.
    ///   - irDir: where `<specName>.ir.json` files live.
    @discardableResult
    public static func run(
        nitroJSONPath: String,
        outDir: String,
        irDir: String
    ) throws -> [String] {
        guard let config = try AlongsideConfig.load(nitroJSONPath: nitroJSONPath) else { return [] }

        let moduleDir = URL(fileURLWithPath: nitroJSONPath).deletingLastPathComponent()
        let userSwiftDir = URL(fileURLWithPath: config.userSwiftDir, relativeTo: moduleDir)
        let irDirURL = URL(fileURLWithPath: irDir, isDirectory: true)
        let outDirURL = URL(fileURLWithPath: outDir, isDirectory: true)
        // Flat, with no `android/` level, because the whole tree is ours and this
        // pass is Android-only: iOS goes through nitrogen's own Swift output,
        // never through here.
        let bridgeDir = outDirURL.appendingPathComponent("swift", isDirectory: true)
        let glueDir = outDirURL.appendingPathComponent("c++", isDirectory: true)

        // Resolve and emit everything before writing anything: a spec that
        // fails validation halfway through should not leave a half-written
        // tree behind for the next build to trip over.
        var files: [(url: URL, contents: String)] = []
        for entry in config.entries {
            let object = try loadIR(spec: entry, in: irDirURL)

            let userSwift = userSwiftDir.appendingPathComponent("\(entry.className).swift")
            guard FileManager.default.fileExists(atPath: userSwift.path) else {
                throw AlongsideError.missingUserSwift(
                    className: entry.className, expectedPath: userSwift.path)
            }

            files.append((
                bridgeDir.appendingPathComponent("\(entry.className)+CBridge.swift"),
                try CBridgeEmitter.emit(object)
            ))
            files.append((
                glueDir.appendingPathComponent("\(entry.className).hpp"),
                try CppGlueEmitter.emit(object, namespace: config.qualifiedNamespace)
            ))
        }

        files.append((
            outDirURL.appendingPathComponent("\(config.hostLibraryName)+swift-embedded.cmake"),
            CMakeFragmentEmitter.emit(
                hostLibraryName: config.hostLibraryName,
                userSwiftDir: config.userSwiftDir,
                classNames: config.entries.map(\.className)
            )
        ))

        var written: [String] = []
        for file in files {
            try FileManager.default.createDirectory(
                at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: file.url, atomically: true, encoding: .utf8)
            written.append(file.url.path)
        }
        return written
    }

    /// `<irDir>/<specName>.ir.json`, narrowed to the one object the entry names.
    /// The IR is keyed by spec name but the class name is authoritative, because
    /// a file may carry several HybridObjects.
    private static func loadIR(spec entry: AlongsideConfig.Entry, in irDir: URL) throws -> HybridObjectIR {
        let irPath = irDir.appendingPathComponent("\(entry.specName).ir.json")
        guard FileManager.default.fileExists(atPath: irPath.path) else {
            throw AlongsideError.missingIR(spec: entry.specName, expectedPath: irPath.path)
        }
        let objects = try IRJSONCodec.decode(try Data(contentsOf: irPath))
        guard let object = objects.first(where: { $0.className == entry.className }) else {
            throw AlongsideError.missingIR(spec: entry.specName, expectedPath: irPath.path)
        }
        return object
    }
}
