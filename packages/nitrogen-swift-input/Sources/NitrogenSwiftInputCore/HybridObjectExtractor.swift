import Foundation
import SwiftParser
import SwiftSyntax

/// Walks a Swift source tree and extracts `Hybrid<Name>` class declarations
/// into `HybridObjectIR`. The user's Swift code stays standard Swift —
/// nothing here requires a custom attribute or macro, so the project compiles
/// before nitrogen ever runs.
///
/// Platform bindings are *not* read from the source. The CLI passes them in
/// via flags, mirroring how the BridgeJS adapter works. This keeps the two
/// front-ends symmetric and avoids needing a fictional `@HybridObject(...)`
/// attribute that the Swift compiler would reject.
public enum HybridObjectExtractor {
    public static func extract(
        source: String,
        platforms: [PlatformBinding],
        fileName: String = "<input>"
    ) throws -> [HybridObjectIR] {
        // `platforms` is stamped onto every IR produced by this call. An empty
        // list is valid here — the CLI resolves platforms per spec (CLI flag
        // OR nitro.json autolinking) and rebuilds the IR before emit, where a
        // non-empty platforms list is enforced.
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: fileName, tree: tree)
        let visitor = HybridObjectVisitor(
            viewMode: .sourceAccurate,
            converter: converter,
            fileName: fileName,
            platforms: platforms
        )
        visitor.walk(tree)
        if let diagnostic = visitor.firstDiagnostic {
            throw diagnostic
        }
        return visitor.results
    }
}

private final class HybridObjectVisitor: SyntaxVisitor {
    private let converter: SourceLocationConverter
    private let fileName: String
    private let platforms: [PlatformBinding]
    var results: [HybridObjectIR] = []
    var firstDiagnostic: Diagnostic?

    init(
        viewMode: SyntaxTreeViewMode,
        converter: SourceLocationConverter,
        fileName: String,
        platforms: [PlatformBinding]
    ) {
        self.converter = converter
        self.fileName = fileName
        self.platforms = platforms
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let className = node.name.text
        guard isHybridObjectClassName(className) else {
            return .visitChildren
        }
        do {
            let location = sourceLocation(for: node)
            let methods = try MethodExtractor.extractMethods(
                from: node.memberBlock,
                fileName: fileName,
                converter: converter
            )
            results.append(
                HybridObjectIR(
                    className: className,
                    platforms: platforms,
                    methods: methods,
                    sourceLocation: location
                )
            )
        } catch let diagnostic as Diagnostic {
            if firstDiagnostic == nil {
                firstDiagnostic = diagnostic
            }
        } catch {
            if firstDiagnostic == nil {
                firstDiagnostic = Diagnostic(message: "\(error)")
            }
        }
        return .visitChildren
    }

    /// `Hybrid` is the matching prefix; the bare name `Hybrid` doesn't qualify
    /// (no spec name to derive). Matches the Nitro convention used elsewhere
    /// in this repo: impl class `HybridFoo` ↔ TS interface `Foo`.
    private func isHybridObjectClassName(_ name: String) -> Bool {
        guard name.hasPrefix("Hybrid"), name.count > "Hybrid".count else {
            return false
        }
        return true
    }

    private func sourceLocation(for node: some SyntaxProtocol) -> SourceLocationIR {
        let location = node.startLocation(converter: converter)
        return SourceLocationIR(
            file: fileName,
            line: location.line,
            column: location.column
        )
    }
}
