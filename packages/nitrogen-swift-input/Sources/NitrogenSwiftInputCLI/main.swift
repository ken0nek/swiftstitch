import Foundation
import NitrogenSwiftInputCore

// nitrogen-swift-input
//
// Reads `Hybrid<Name>` Swift class declarations and emits the equivalent
// `.nitro.ts` spec for downstream `nitrogen` consumption. The input Swift
// stays standard Swift — no fictional `@HybridObject(...)` attribute, so the
// user's project compiles before this tool ever runs.
//
// Usage:
//   nitrogen-swift-input init <Name> [--out <dir>] [--ios <lang>] [--android <lang>] [--force]
//   nitrogen-swift-input emit [--input <swift-file> ...] [--out <dir>] [--out-json <dir>]
//                             [--ios <lang>] [--android <lang>]
//
// Both subcommands favor convention over configuration: `emit` with no flags
// globs `swift/Hybrid*.swift`, writes to `specs/`, and reads per-spec
// platforms from `nitro.json` autolinking. `init` writes the Swift starter
// then chains into a first `emit` so the user sees the full output tree
// on the very first invocation.
//
// JSON output is the contract for the TS spec adapter
// (`nitrogen-swift-spec-input`) consumes it and constructs nitrogen's
// internal `HybridObjectSpec` instances directly, no `.nitro.ts` artifact.

enum CLIError: Error, CustomStringConvertible {
    case missingArgument(String)
    case unknownArgument(String)
    case noInputs(scannedDir: String)
    case noPlatformsForSpec(String)
    case invalidLanguage(flag: String, value: String)
    case readFailed(String, underlying: String)
    case parseFailed(Diagnostic)
    case writeFailed(String, underlying: String)
    case invalidName(String)
    case fileExists(String)
    case nitroJSON(NitroJSONError)

    var description: String {
        switch self {
        case .missingArgument(let arg): return "missing argument: \(arg)"
        case .unknownArgument(let arg): return "unknown argument: \(arg)"
        case .noInputs(let dir):
            return "no `Hybrid*.swift` files in \(dir)/ (pass --input <path> if your sources live elsewhere)"
        case .noPlatformsForSpec(let spec):
            return "no platforms for spec `\(spec)` — pass --ios <lang> / --android <lang> or add `autolinking.\(spec)` to nitro.json"
        case .invalidLanguage(let flag, let value):
            return "\(flag): unsupported language `\(value)` (expected swift / kotlin / cpp)"
        case .readFailed(let path, let err): return "could not read \(path): \(err)"
        case .parseFailed(let diag): return diag.description
        case .writeFailed(let path, let err): return "could not write \(path): \(err)"
        case .invalidName(let name):
            return "'\(name)' is not a valid spec name (expected a Swift identifier like `Counter`)"
        case .fileExists(let path):
            return "\(path) already exists (pass --force to overwrite)"
        case .nitroJSON(let err): return "\(err)"
        }
    }
}

struct EmitOptions {
    var inputs: [String] = []
    var outDir: String?
    var outJSONDir: String?
    var platforms: [PlatformBinding] = []
}

/// Where the CLI looks for nitro.json. Resolved relative to the current
/// working directory so per-package scripts (`cd <pkg> && nitrogen-swift-input emit`)
/// pick up the right one without any flag.
let defaultNitroJSONPath = "nitro.json"
let defaultSwiftSourceDir = "swift"
let defaultSpecsDir = "specs"

func parseLanguage(_ value: String, flag: String) throws -> Language {
    switch value {
    case "swift": return .swift
    case "kotlin": return .kotlin
    case "cpp", "c++": return .cpp
    default:
        throw CLIError.invalidLanguage(flag: flag, value: value)
    }
}

func parseEmitOptions(_ argv: ArraySlice<String>) throws -> EmitOptions {
    var options = EmitOptions()
    var iterator = argv.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--input":
            guard let value = iterator.next() else { throw CLIError.missingArgument("--input <path>") }
            options.inputs.append(value)
        case "--out":
            guard let value = iterator.next() else { throw CLIError.missingArgument("--out <dir>") }
            options.outDir = value
        case "--out-json":
            guard let value = iterator.next() else { throw CLIError.missingArgument("--out-json <dir>") }
            options.outJSONDir = value
        case "--ios":
            guard let value = iterator.next() else { throw CLIError.missingArgument("--ios <lang>") }
            options.platforms.append(
                PlatformBinding(platform: .ios, language: try parseLanguage(value, flag: "--ios"))
            )
        case "--android":
            guard let value = iterator.next() else { throw CLIError.missingArgument("--android <lang>") }
            options.platforms.append(
                PlatformBinding(platform: .android, language: try parseLanguage(value, flag: "--android"))
            )
        default:
            throw CLIError.unknownArgument(arg)
        }
    }
    // Inputs / outputs / platforms are validated at runtime where defaults
    // (glob `swift/Hybrid*.swift`, `specs/`, nitro.json autolinking) can fill
    // in for missing flags.
    return options
}

/// Glob `<dir>/Hybrid*.swift`. Returns an empty array if the directory is
/// missing — the caller decides whether that's an error.
func discoverDefaultInputs(in dir: String) -> [String] {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
        return []
    }
    return entries
        .filter { $0.hasPrefix("Hybrid") && $0.hasSuffix(".swift") }
        .map { (dir as NSString).appendingPathComponent($0) }
        .sorted()
}

/// Per-spec platform resolution. CLI flags win wholesale when present —
/// mixing per-platform from CLI and nitro.json gets confusing. Otherwise
/// fall back to whatever `autolinking.<SpecName>` declares.
func resolvePlatforms(
    specName: String,
    cliFlags: [PlatformBinding],
    nitroJSON: NitroJSON?
) -> [PlatformBinding] {
    if !cliFlags.isEmpty { return cliFlags }
    return NitroJSONReader.platforms(for: specName, in: nitroJSON)
}

func loadSource(at path: String) throws -> String {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        throw CLIError.readFailed(path, underlying: "\(error)")
    }
}

func writeFile(_ contents: String, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let parent = url.deletingLastPathComponent()
    do {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        throw CLIError.writeFailed(path, underlying: "\(error)")
    }
}

func writeFileData(_ data: Data, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let parent = url.deletingLastPathComponent()
    do {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        // Append a trailing newline for POSIX text-file convention.
        if let handle = try? FileHandle(forWritingTo: url) {
            try handle.seekToEnd()
            handle.write(Data("\n".utf8))
            try handle.close()
        }
    } catch {
        throw CLIError.writeFailed(path, underlying: "\(error)")
    }
}

func runEmit(_ argv: ArraySlice<String>) throws {
    let options = try parseEmitOptions(argv)
    try executeEmit(options: options)
}

func executeEmit(options: EmitOptions) throws {
    // 1. Load nitro.json once, if present. Missing file is fine; malformed is
    //    not. This has to happen before input discovery: `swiftstitch.userSwiftDir`
    //    names the directory to scan, so reading it later would leave the
    //    setting declarable-but-unhonored.
    let nitroJSON: NitroJSON?
    do {
        nitroJSON = try NitroJSONReader.load(at: defaultNitroJSONPath)
    } catch let err as NitroJSONError {
        throw CLIError.nitroJSON(err)
    }

    // 2. Resolve inputs (defaulted glob if --input wasn't supplied). Explicit
    //    --input still wins wholesale; otherwise scan whatever
    //    `swiftstitch.userSwiftDir` declares, falling back to `swift/`.
    let swiftSourceDir = nitroJSON?.swiftstitch?.userSwiftDir ?? defaultSwiftSourceDir
    let inputs = options.inputs.isEmpty
        ? discoverDefaultInputs(in: swiftSourceDir)
        : options.inputs
    if inputs.isEmpty {
        throw CLIError.noInputs(scannedDir: swiftSourceDir)
    }

    // 3. Resolve outputs (default both to `specs/` only when neither is set;
    //    if the user named one explicitly we honor the "TS-only" / "JSON-only"
    //    opt-in).
    let outDir: String?
    let outJSONDir: String?
    if options.outDir == nil, options.outJSONDir == nil {
        outDir = defaultSpecsDir
        outJSONDir = defaultSpecsDir
    } else {
        outDir = options.outDir
        outJSONDir = options.outJSONDir
    }

    // 4. Parse each input with empty platforms — we re-stamp per spec next.
    var perFile: [(input: String, objects: [HybridObjectIR])] = []
    for input in inputs {
        let source = try loadSource(at: input)
        do {
            let objects = try HybridObjectExtractor.extract(
                source: source,
                platforms: [],
                fileName: (input as NSString).lastPathComponent
            )
            perFile.append((input, objects))
        } catch let diagnostic as Diagnostic {
            throw CLIError.parseFailed(diagnostic)
        }
    }

    // 5. Per-spec platform resolution. Each IR gets re-built with its resolved
    //    bindings; empty after resolution is a hard error.
    var resolvedPerFile: [(input: String, objects: [HybridObjectIR])] = []
    for (input, objects) in perFile {
        var resolved: [HybridObjectIR] = []
        for obj in objects {
            let platforms = resolvePlatforms(
                specName: obj.specName,
                cliFlags: options.platforms,
                nitroJSON: nitroJSON
            )
            if platforms.isEmpty {
                throw CLIError.noPlatformsForSpec(obj.specName)
            }
            resolved.append(
                HybridObjectIR(
                    className: obj.className,
                    platforms: platforms,
                    methods: obj.methods,
                    sourceLocation: obj.sourceLocation
                )
            )
        }
        resolvedPerFile.append((input, resolved))
    }

    // 6. Emit. One `.nitro.ts` and/or one `.ir.json` per spec, per input.
    if let outDir = outDir {
        for (input, objects) in resolvedPerFile {
            guard let first = objects.first else {
                FileHandle.standardError.write(Data("warning: no `Hybrid<Name>` class in \(input)\n".utf8))
                continue
            }
            let ts = NitroTSEmitter.emit(objects)
            let outPath = (outDir as NSString).appendingPathComponent("\(first.specName).nitro.ts")
            try writeFile(ts, to: outPath)
            print("ok: wrote \(outPath)")
        }
    }

    if let outJSONDir = outJSONDir {
        for (input, objects) in resolvedPerFile {
            guard let first = objects.first else {
                if outDir == nil {
                    FileHandle.standardError.write(Data("warning: no `Hybrid<Name>` class in \(input)\n".utf8))
                }
                continue
            }
            do {
                let data = try IRJSONCodec.encode(objects)
                let outPath = (outJSONDir as NSString).appendingPathComponent("\(first.specName).ir.json")
                try writeFileData(data, to: outPath)
                print("ok: wrote \(outPath)")
            } catch let diagnostic as Diagnostic {
                throw CLIError.parseFailed(diagnostic)
            }
        }
    }
}

struct InitOptions {
    var name: String
    var outDir: String = defaultSwiftSourceDir
    var force: Bool = false
    /// Platforms to stamp on the first emit run that follows `init`. Defaults
    /// to `ios: swift, android: kotlin` — the common case for stock Nitro
    /// projects without alongside-pass. Users override with --ios / --android.
    var platforms: [PlatformBinding] = [
        PlatformBinding(platform: .ios, language: .swift),
        PlatformBinding(platform: .android, language: .kotlin),
    ]
}

func parseInitOptions(_ argv: ArraySlice<String>) throws -> InitOptions {
    var name: String? = nil
    var outDir: String = defaultSwiftSourceDir
    var force: Bool = false
    var platformOverrides: [PlatformBinding] = []
    var iterator = argv.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--out":
            guard let value = iterator.next() else { throw CLIError.missingArgument("--out <dir>") }
            outDir = value
        case "--force":
            force = true
        case "--ios":
            guard let value = iterator.next() else { throw CLIError.missingArgument("--ios <lang>") }
            platformOverrides.append(
                PlatformBinding(platform: .ios, language: try parseLanguage(value, flag: "--ios"))
            )
        case "--android":
            guard let value = iterator.next() else { throw CLIError.missingArgument("--android <lang>") }
            platformOverrides.append(
                PlatformBinding(platform: .android, language: try parseLanguage(value, flag: "--android"))
            )
        default:
            if arg.hasPrefix("--") {
                throw CLIError.unknownArgument(arg)
            }
            if name != nil {
                throw CLIError.unknownArgument(arg)
            }
            name = arg
        }
    }
    guard let resolvedName = name else {
        throw CLIError.missingArgument("<Name>")
    }
    var options = InitOptions(name: resolvedName, outDir: outDir, force: force)
    if !platformOverrides.isEmpty {
        options.platforms = platformOverrides
    }
    return options
}

func runInit(_ argv: ArraySlice<String>) throws {
    let options = try parseInitOptions(argv)
    let specName: String
    do {
        specName = try InitTemplate.normalize(rawName: options.name)
    } catch let err as InitTemplateError {
        switch err {
        case .invalidName(let raw):
            throw CLIError.invalidName(raw)
        }
    }
    let className = "Hybrid\(specName)"
    let path = (options.outDir as NSString).appendingPathComponent("\(className).swift")
    if FileManager.default.fileExists(atPath: path), !options.force {
        throw CLIError.fileExists(path)
    }
    let body = InitTemplate.render(specName: specName)
    try writeFile(body, to: path)
    print("ok: wrote \(path)")

    // Chain into a first emit so the user sees `specs/<Name>.nitro.ts` and
    // `.ir.json` materialize on the same command. Use the init's own --ios /
    // --android (with sensible defaults) — at init time the user may not yet
    // have added the spec to nitro.json.
    var emitOptions = EmitOptions()
    emitOptions.inputs = [path]
    emitOptions.platforms = options.platforms
    // Leave outDir / outJSONDir nil so `executeEmit` defaults both to specs/.
    try executeEmit(options: emitOptions)

    print("next: bun nitrogen \(defaultSpecsDir) && pod install")
}

let allArgs = CommandLine.arguments
guard allArgs.count >= 2 else {
    FileHandle.standardError.write(
        Data("""
        usage:
          nitrogen-swift-input init <Name> [--out <dir>] [--ios <lang>] [--android <lang>] [--force]
          nitrogen-swift-input emit [--input <swift-file> ...] [--out <dir>] [--out-json <dir>] [--ios <lang>] [--android <lang>]

        Both commands favor zero-flag defaults: `swift/Hybrid*.swift` as input,
        `specs/` as output, and per-spec platforms from `nitro.json` autolinking.

        """.utf8)
    )
    exit(64)
}

do {
    let subcommand = allArgs[1]
    let rest = allArgs[2...]
    switch subcommand {
    case "emit":
        try runEmit(rest)
    case "init":
        try runInit(rest)
    default:
        throw CLIError.unknownArgument(subcommand)
    }
} catch let cliError as CLIError {
    FileHandle.standardError.write(Data("error: \(cliError)\n".utf8))
    exit(65)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(70)
}
