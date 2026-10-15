import SwiftParser
import SwiftSyntax

/// Minimal smoke API: parse a Swift source string and report whether it has any
/// syntax errors. Used to prove the swift-syntax dependency is
/// wired up before adding real `@HybridObject` extraction.
public enum SmokeParse {
    public static func hasSyntaxErrors(_ source: String) -> Bool {
        let tree = Parser.parse(source: source)
        return tree.hasError
    }

    public static func topLevelDeclCount(_ source: String) -> Int {
        let tree = Parser.parse(source: source)
        return tree.statements.count
    }
}
