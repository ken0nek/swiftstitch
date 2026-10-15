import Foundation
import NitrogenSwiftEmbeddedCore
import NitrogenSwiftInputCore

// CLI:
//   nitrogen-swift-embedded emit      --ir <path> --out <dir>
//   nitrogen-swift-embedded emit-cpp  --ir <path> --out <dir> --namespace <ns>
//   nitrogen-swift-embedded compile   --ir <path> --user-swift <p>... \
//                                     --bridge-dir <dir> --out-o <path> \
//                                     [--arch aarch64|x86_64|armv7] \
//                                     --swiftc <path>
//   nitrogen-swift-embedded alongside --nitro-json <path> \
//                                     [--out-dir <dir>] [--ir-dir <dir>]
//
// `emit` produces +CBridge.swift (Swift @c shims).
// `emit-cpp` produces <Class>.hpp (the C++ subclass that forwards to @c).
// `compile` invokes a Swift 6.3+ toolchain to produce the Android-NDK-linkable
// `.o` for the host `.so`.
// `alongside` runs after `bunx nitrogen` and does all three of the above's
// emitting for every spec in nitro.json's `swiftstitch` block, into
// `swiftstitch/generated/`, our tree, outside the one nitrogen sweeps.

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case fileNotFound(String)
    case ioError(String)

    var description: String {
        switch self {
        case .usage(let msg): return "usage: \(msg)"
        case .fileNotFound(let path): return "file not found: \(path)"
        case .ioError(let msg): return "io error: \(msg)"
        }
    }
}

func runEmit(_ iter: inout IndexingIterator<[String]>) throws {
    var irPath: String?
    var outPath: String?
    while let arg = iter.next() {
        switch arg {
        case "--ir":
            irPath = iter.next()
        case "--out":
            outPath = iter.next()
        default:
            throw CLIError.usage("unknown flag `\(arg)`")
        }
    }
    guard let ir = irPath else { throw CLIError.usage("--ir is required") }
    guard let out = outPath else { throw CLIError.usage("--out is required") }

    let irURL = URL(fileURLWithPath: ir)
    guard FileManager.default.fileExists(atPath: irURL.path) else {
        throw CLIError.fileNotFound(ir)
    }
    let data = try Data(contentsOf: irURL)
    let objects = try IRJSONCodec.decode(data)

    let outURL = URL(fileURLWithPath: out, isDirectory: true)
    try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

    for object in objects {
        let bridge = try CBridgeEmitter.emit(object)
        let fileURL = outURL.appendingPathComponent("\(object.className)+CBridge.swift")
        try bridge.write(to: fileURL, atomically: true, encoding: .utf8)
        FileHandle.standardOutput.write(Data("emitted \(fileURL.path)\n".utf8))
    }
}

func runEmitCpp(_ iter: inout IndexingIterator<[String]>) throws {
    var irPath: String?
    var outPath: String?
    var namespace: String?
    while let arg = iter.next() {
        switch arg {
        case "--ir": irPath = iter.next()
        case "--out": outPath = iter.next()
        case "--namespace": namespace = iter.next()
        default:
            throw CLIError.usage("unknown flag `\(arg)`")
        }
    }
    guard let ir = irPath else { throw CLIError.usage("--ir is required") }
    guard let out = outPath else { throw CLIError.usage("--out is required") }
    guard let ns = namespace else { throw CLIError.usage("--namespace is required") }

    let irURL = URL(fileURLWithPath: ir)
    guard FileManager.default.fileExists(atPath: irURL.path) else {
        throw CLIError.fileNotFound(ir)
    }
    let data = try Data(contentsOf: irURL)
    let objects = try IRJSONCodec.decode(data)

    let outURL = URL(fileURLWithPath: out, isDirectory: true)
    try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

    for object in objects {
        let cpp = try CppGlueEmitter.emit(object, namespace: ns)
        let fileURL = outURL.appendingPathComponent("\(object.className).hpp")
        try cpp.write(to: fileURL, atomically: true, encoding: .utf8)
        FileHandle.standardOutput.write(Data("emitted \(fileURL.path)\n".utf8))
    }
}

func runCompile(_ iter: inout IndexingIterator<[String]>) throws {
    var irPath: String?
    var userSwift: [String] = []
    var bridgeDir: String?
    var outO: String?
    var arch: EmbeddedCompiler.Architecture = .aarch64
    var swiftcPath: String?
    while let arg = iter.next() {
        switch arg {
        case "--ir": irPath = iter.next()
        case "--user-swift": if let v = iter.next() { userSwift.append(v) }
        case "--bridge-dir": bridgeDir = iter.next()
        case "--out-o": outO = iter.next()
        case "--arch":
            if let v = iter.next(), let parsed = EmbeddedCompiler.Architecture(rawValue: v) {
                arch = parsed
            } else {
                throw CLIError.usage("--arch must be one of: aarch64, x86_64, armv7")
            }
        case "--swiftc": swiftcPath = iter.next()
        default:
            throw CLIError.usage("unknown flag `\(arg)`")
        }
    }
    guard let ir = irPath else { throw CLIError.usage("--ir is required") }
    guard let bridgeDirIn = bridgeDir else { throw CLIError.usage("--bridge-dir is required") }
    guard let outOIn = outO else { throw CLIError.usage("--out-o is required") }
    guard let swiftc = swiftcPath else { throw CLIError.usage("--swiftc is required") }
    guard !userSwift.isEmpty else { throw CLIError.usage("at least one --user-swift is required") }

    let irURL = URL(fileURLWithPath: ir)
    let irData = try Data(contentsOf: irURL)
    let objects = try IRJSONCodec.decode(irData)

    let bridgeDirURL = URL(fileURLWithPath: bridgeDirIn, isDirectory: true)
    let bridgeFiles = objects.map {
        bridgeDirURL.appendingPathComponent("\($0.className)+CBridge.swift")
    }
    for url in bridgeFiles where !FileManager.default.fileExists(atPath: url.path) {
        throw CLIError.fileNotFound(url.path)
    }

    let inputs = EmbeddedCompiler.Inputs(
        userSwiftFiles: userSwift.map { URL(fileURLWithPath: $0) },
        bridgeSwiftFiles: bridgeFiles,
        outputObjectFile: URL(fileURLWithPath: outOIn),
        architecture: arch,
        swiftcPath: URL(fileURLWithPath: swiftc)
    )
    _ = try EmbeddedCompiler().compile(inputs)
    FileHandle.standardOutput.write(Data("compiled \(outOIn) (\(arch.rawValue))\n".utf8))
}

func runAlongside(_ iter: inout IndexingIterator<[String]>) throws {
    var nitroJSONPath: String?
    var outDir: String?
    var irDir: String?
    while let arg = iter.next() {
        switch arg {
        case "--nitro-json": nitroJSONPath = iter.next()
        case "--out-dir": outDir = iter.next()
        case "--ir-dir": irDir = iter.next()
        default:
            throw CLIError.usage("unknown flag `\(arg)`")
        }
    }
    guard let nitroJSON = nitroJSONPath else { throw CLIError.usage("--nitro-json is required") }

    // Unlike `nitrogen-swift-input emit`, where nitro.json is an optional
    // convenience input, it is this subcommand's only input. So a path that
    // isn't there is a misconfiguration, not a module that opted out. Without
    // this the pass would report "no `swiftstitch` block", which would be a
    // false statement about a file it never read.
    let nitroJSONURL = URL(fileURLWithPath: nitroJSON)
    guard FileManager.default.fileExists(atPath: nitroJSONURL.path) else {
        throw CLIError.fileNotFound(nitroJSON)
    }

    // The IR and output directories are module-relative conventions (`specs/`,
    // what `nitrogen-swift-input emit` writes; `swiftstitch/generated/`, our
    // own tree), so resolve both against nitro.json's directory rather than
    // the caller's cwd.
    let moduleDir = nitroJSONURL.deletingLastPathComponent()
    let resolvedIRDir = URL(fileURLWithPath: irDir ?? "specs", relativeTo: moduleDir).path
    let resolvedOutDir = URL(
        fileURLWithPath: outDir ?? "swiftstitch/generated", relativeTo: moduleDir).path

    let written = try AlongsideRunner.run(
        nitroJSONPath: nitroJSON,
        outDir: resolvedOutDir,
        irDir: resolvedIRDir
    )
    guard !written.isEmpty else {
        FileHandle.standardOutput.write(
            Data("alongside: no `swiftstitch` block in \(nitroJSON), nothing to do\n".utf8))
        return
    }
    for path in written {
        FileHandle.standardOutput.write(Data("emitted \(path)\n".utf8))
    }
}

func run(_ argv: [String]) throws {
    var iter = argv.makeIterator()
    _ = iter.next()
    guard let command = iter.next() else {
        throw CLIError.usage("nitrogen-swift-embedded emit|emit-cpp|compile|alongside ...")
    }
    switch command {
    case "emit":
        try runEmit(&iter)
    case "emit-cpp":
        try runEmitCpp(&iter)
    case "compile":
        try runCompile(&iter)
    case "alongside":
        try runAlongside(&iter)
    default:
        throw CLIError.usage("unknown command `\(command)` (use emit|emit-cpp|compile|alongside)")
    }
}

do {
    try run(CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
