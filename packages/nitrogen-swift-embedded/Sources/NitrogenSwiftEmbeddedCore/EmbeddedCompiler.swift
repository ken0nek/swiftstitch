import Foundation

/// Drives swiftc to compile a HybridObject's Swift source + the generated
/// `@c` bridge into an Android-linkable object file. Targets `*-none-none-elf`
/// (Embedded Swift; no OS, no runtime), which the Android NDK links into the
/// host `.so` because aarch64/x86_64/armv7 ELF + AAPCS calling conventions
/// match Android's bionic ABI.
public struct EmbeddedCompiler {
    public enum Architecture: String, CaseIterable, Sendable {
        case aarch64
        case x86_64
        case armv7

        public var embeddedTriple: String {
            switch self {
            case .aarch64: return "aarch64-none-none-elf"
            case .x86_64: return "x86_64-unknown-none-elf"
            case .armv7: return "armv7-none-none-eabi"
            }
        }
    }

    public struct Inputs: Sendable {
        public let userSwiftFiles: [URL]
        public let bridgeSwiftFiles: [URL]
        public let outputObjectFile: URL
        public let architecture: Architecture
        public let swiftcPath: URL

        public init(
            userSwiftFiles: [URL],
            bridgeSwiftFiles: [URL],
            outputObjectFile: URL,
            architecture: Architecture,
            swiftcPath: URL
        ) {
            self.userSwiftFiles = userSwiftFiles
            self.bridgeSwiftFiles = bridgeSwiftFiles
            self.outputObjectFile = outputObjectFile
            self.architecture = architecture
            self.swiftcPath = swiftcPath
        }
    }

    public enum CompilerError: Error, CustomStringConvertible {
        case swiftcMissing(URL)
        case swiftcFailed(exitCode: Int32, stderr: String)
        case noSources

        public var description: String {
            switch self {
            case .swiftcMissing(let url):
                return "swiftc not found at \(url.path)"
            case .swiftcFailed(let code, let stderr):
                return "swiftc exited \(code):\n\(stderr)"
            case .noSources:
                return "no Swift sources to compile"
            }
        }
    }

    public init() {}

    /// Runs swiftc and returns the produced object file URL on success.
    @discardableResult
    public func compile(_ inputs: Inputs) throws -> URL {
        guard !inputs.userSwiftFiles.isEmpty || !inputs.bridgeSwiftFiles.isEmpty else {
            throw CompilerError.noSources
        }
        guard FileManager.default.fileExists(atPath: inputs.swiftcPath.path) else {
            throw CompilerError.swiftcMissing(inputs.swiftcPath)
        }

        let outDir = inputs.outputObjectFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var args: [String] = [
            "-target", inputs.architecture.embeddedTriple,
            "-enable-experimental-feature", "Embedded",
            "-enable-experimental-feature", "CImplementation",
            "-wmo",
            "-parse-as-library",
            "-c",
            "-o", inputs.outputObjectFile.path,
        ]
        for file in inputs.userSwiftFiles { args.append(file.path) }
        for file in inputs.bridgeSwiftFiles { args.append(file.path) }

        let proc = Process()
        proc.executableURL = inputs.swiftcPath
        proc.arguments = args
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8) ?? ""
            throw CompilerError.swiftcFailed(exitCode: proc.terminationStatus, stderr: stderr)
        }
        return inputs.outputObjectFile
    }
}
