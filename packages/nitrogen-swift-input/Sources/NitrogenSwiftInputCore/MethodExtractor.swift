import SwiftSyntax

enum MethodExtractor {
    static func extractMethods(
        from memberBlock: MemberBlockSyntax,
        fileName: String,
        converter: SourceLocationConverter
    ) throws -> [MethodIR] {
        var methods: [MethodIR] = []
        for member in memberBlock.members {
            guard let function = member.decl.as(FunctionDeclSyntax.self) else {
                continue
            }
            guard hasPublicModifier(function) else {
                continue
            }
            let location = function.startLocation(converter: converter)
            let methodLocation = SourceLocationIR(
                file: fileName,
                line: location.line,
                column: location.column
            )
            let parameters = try parseParameters(
                function.signature.parameterClause.parameters,
                methodName: function.name.text,
                fileName: fileName,
                converter: converter
            )
            let returnType = try parseReturnType(
                function.signature.returnClause,
                methodName: function.name.text,
                location: methodLocation
            )
            let isThrowing = function.signature.effectSpecifiers?.throwsSpecifier != nil
            methods.append(
                MethodIR(
                    name: function.name.text,
                    parameters: parameters,
                    returnType: returnType,
                    isThrowing: isThrowing
                )
            )
        }
        return methods
    }

    private static func hasPublicModifier(_ function: FunctionDeclSyntax) -> Bool {
        for modifier in function.modifiers {
            if modifier.name.tokenKind == .keyword(.public) {
                return true
            }
        }
        return false
    }

    private static func parseParameters(
        _ parameters: FunctionParameterListSyntax,
        methodName: String,
        fileName: String,
        converter: SourceLocationConverter
    ) throws -> [ParameterIR] {
        var result: [ParameterIR] = []
        for parameter in parameters {
            let location = parameter.startLocation(converter: converter)
            let paramLocation = SourceLocationIR(
                file: fileName,
                line: location.line,
                column: location.column
            )
            let label = resolveParameterLabel(parameter)
            let type = try parseType(
                parameter.type,
                context: "parameter `\(label)` of `\(methodName)`",
                location: paramLocation
            )
            result.append(ParameterIR(label: label, type: type))
        }
        return result
    }

    private static func resolveParameterLabel(
        _ parameter: FunctionParameterSyntax
    ) -> String {
        let firstName = parameter.firstName.text
        if firstName == "_" {
            return parameter.secondName?.text ?? firstName
        }
        return firstName
    }

    private static func parseReturnType(
        _ clause: ReturnClauseSyntax?,
        methodName: String,
        location: SourceLocationIR
    ) throws -> TypeIR {
        guard let clause else { return .void }
        return try parseType(
            clause.type,
            context: "return type of `\(methodName)`",
            location: location
        )
    }

    private static func parseType(
        _ type: TypeSyntax,
        context: String,
        location: SourceLocationIR
    ) throws -> TypeIR {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            switch identifier.name.text {
            case "Int64": return .int64
            case "UInt64": return .uint64
            case "Double": return .double
            case "Float": return .float
            case "Bool": return .bool
            case "Void": return .void
            case "Int", "Int8", "Int16", "Int32",
                 "UInt", "UInt8", "UInt16", "UInt32",
                 "String",
                 "Optional",
                 "Array":
                throw Diagnostic(
                    message: "Type `\(identifier.name.text)` not supported in the int/number-only scope of \(context). Supported: Int64, UInt64, Double, Float, Bool, Void.",
                    location: location
                )
            default:
                throw Diagnostic(
                    message: "Unsupported type `\(identifier.name.text)` in \(context). Supported: Int64, UInt64, Double, Float, Bool, Void.",
                    location: location
                )
            }
        }
        if type.is(TupleTypeSyntax.self), type.trimmedDescription == "()" {
            return .void
        }
        throw Diagnostic(
            message: "Unsupported type `\(type.trimmedDescription)` in \(context). Supported: Int64, UInt64, Double, Float, Bool, Void.",
            location: location
        )
    }
}
