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
//
// `emit` produces +CBridge.swift (Swift @c shims).
// `emit-cpp` produces <Class>.hpp (the C++ subclass that forwards to @c).
// `compile` invokes a Swift 6.3+ toolchain to produce the Android-NDK-linkable
// `.o` for the host `.so`.

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

func run(_ argv: [String]) throws {
    var iter = argv.makeIterator()
    _ = iter.next()
    guard let command = iter.next() else {
        throw CLIError.usage("nitrogen-swift-embedded emit|compile ...")
    }
    switch command {
    case "emit":
        try runEmit(&iter)
    case "emit-cpp":
        try runEmitCpp(&iter)
    case "compile":
        try runCompile(&iter)
    default:
        throw CLIError.usage("unknown command `\(command)` (use emit|emit-cpp|compile)")
    }
}

do {
    try run(CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
