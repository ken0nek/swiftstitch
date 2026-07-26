import Foundation

/// JSON-on-disk shape for `HybridObjectIR` and friends. Used as the contract
/// between this Swift CLI and the downstream `nitrogen-swift-spec-input` TS
/// adapter (Phase 1G): we emit JSON here, that package reads it and
/// constructs nitrogen's internal `HybridObjectSpec` instances directly,
/// bypassing the `.nitro.ts` artifact entirely.
public enum IRJSONCodec {
    /// Bumped when the wire format changes incompatibly. Decoders must reject
    /// schema versions they don't recognize so a stale TS adapter can't
    /// silently misread newer Swift CLI output.
    public static let schemaVersion: Int = 1

    public static func encode(_ objects: [HybridObjectIR]) throws -> Data {
        let document = JSONDocument(
            schemaVersion: schemaVersion,
            objects: objects.map(JSONDocument.Object.init(from:))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> [HybridObjectIR] {
        let document = try JSONDecoder().decode(JSONDocument.self, from: data)
        guard document.schemaVersion == schemaVersion else {
            throw Diagnostic(
                message: "unsupported IR schema version \(document.schemaVersion); expected \(schemaVersion)"
            )
        }
        return try document.objects.map { try $0.toIR() }
    }
}

private struct JSONDocument: Codable {
    let schemaVersion: Int
    let objects: [Object]

    struct Object: Codable {
        let className: String
        let specName: String
        let platforms: [Binding]
        let methods: [Method]

        struct Binding: Codable {
            let platform: String
            let language: String
        }

        struct Method: Codable {
            let name: String
            let parameters: [Parameter]
            let returnType: TypeJSON
            let isThrowing: Bool
        }

        struct Parameter: Codable {
            let label: String
            let type: TypeJSON
        }

        struct TypeJSON: Codable {
            let kind: String
        }
    }
}

private extension JSONDocument.Object {
    init(from ir: HybridObjectIR) {
        self.className = ir.className
        self.specName = ir.specName
        self.platforms = ir.platforms.map {
            Binding(platform: $0.platform.rawValue, language: $0.language.rawValue)
        }
        self.methods = ir.methods.map { method in
            Method(
                name: method.name,
                parameters: method.parameters.map {
                    Parameter(label: $0.label, type: TypeJSON(from: $0.type))
                },
                returnType: TypeJSON(from: method.returnType),
                isThrowing: method.isThrowing
            )
        }
    }

    func toIR() throws -> HybridObjectIR {
        let mappedPlatforms = try platforms.map { binding -> PlatformBinding in
            guard let platform = Platform(rawValue: binding.platform) else {
                throw Diagnostic(message: "unknown platform `\(binding.platform)` in IR JSON")
            }
            guard let language = Language(rawValue: binding.language) else {
                throw Diagnostic(message: "unknown language `\(binding.language)` in IR JSON")
            }
            return PlatformBinding(platform: platform, language: language)
        }
        let mappedMethods = try methods.map { method -> MethodIR in
            let params = try method.parameters.map { p in
                ParameterIR(label: p.label, type: try p.type.toIR())
            }
            return MethodIR(
                name: method.name,
                parameters: params,
                returnType: try method.returnType.toIR(),
                isThrowing: method.isThrowing
            )
        }
        return HybridObjectIR(
            className: className,
            platforms: mappedPlatforms,
            methods: mappedMethods
        )
    }
}

private extension JSONDocument.Object.TypeJSON {
    init(from typeIR: TypeIR) {
        switch typeIR {
        case .bool: self.kind = "bool"
        case .double: self.kind = "double"
        case .float: self.kind = "float"
        case .int64: self.kind = "int64"
        case .uint64: self.kind = "uint64"
        case .void: self.kind = "void"
        }
    }

    func toIR() throws -> TypeIR {
        switch kind {
        case "bool": return .bool
        case "double": return .double
        case "float": return .float
        case "int64": return .int64
        case "uint64": return .uint64
        case "void": return .void
        default:
            throw Diagnostic(message: "unknown type kind `\(kind)` in IR JSON")
        }
    }
}
