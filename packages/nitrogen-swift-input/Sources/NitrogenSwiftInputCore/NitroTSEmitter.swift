import Foundation

/// Emits `.nitro.ts` source from `HybridObjectIR` values. Phase 1A.4.
public enum NitroTSEmitter {
    public static func emit(_ objects: [HybridObjectIR]) -> String {
        var lines: [String] = []
        let imports = collectImports(objects)
        lines.append(imports)
        lines.append("")
        for (index, object) in objects.enumerated() {
            lines.append(contentsOf: render(object))
            if index != objects.count - 1 {
                lines.append("")
            }
        }
        // Trailing newline so generated files match the rest of the repo's
        // text-file convention.
        return lines.joined(separator: "\n") + "\n"
    }

    private static func collectImports(_ objects: [HybridObjectIR]) -> String {
        var symbols: Set<String> = ["HybridObject"]
        for object in objects {
            for method in object.methods {
                collectSymbols(method.returnType, into: &symbols)
                for parameter in method.parameters {
                    collectSymbols(parameter.type, into: &symbols)
                }
            }
        }
        let ordered = symbols.sorted()
        let joined = ordered.joined(separator: ", ")
        return "import type { \(joined) } from 'react-native-nitro-modules'"
    }

    private static func collectSymbols(_ type: TypeIR, into set: inout Set<String>) {
        switch type {
        case .int64: set.insert("Int64")
        case .uint64: set.insert("UInt64")
        case .double, .float, .bool, .void:
            break
        }
    }

    private static func render(_ object: HybridObjectIR) -> [String] {
        var lines: [String] = []
        lines.append(
            "export interface \(object.specName) extends HybridObject<\(renderPlatformSpec(object.platforms))> {"
        )
        for method in object.methods {
            lines.append("  " + renderMethod(method))
        }
        lines.append("}")
        return lines
    }

    private static func renderPlatformSpec(_ bindings: [PlatformBinding]) -> String {
        let canonical = Platform.allCases.compactMap { platform in
            bindings.first(where: { $0.platform == platform })
        }
        let entries = canonical.map { "\($0.platform.rawValue): '\($0.language.rawValue)'" }
        return "{ \(entries.joined(separator: "; ")) }"
    }

    private static func renderMethod(_ method: MethodIR) -> String {
        let params = method.parameters
            .map { "\($0.label): \(tsType($0.type))" }
            .joined(separator: ", ")
        return "\(method.name)(\(params)): \(tsType(method.returnType))"
    }

    private static func tsType(_ type: TypeIR) -> String {
        switch type {
        case .int64: return "Int64"
        case .uint64: return "UInt64"
        case .double: return "number"
        case .float: return "number"
        case .bool: return "boolean"
        case .void: return "void"
        }
    }
}
