import Foundation

public enum Platform: String, Hashable, CaseIterable, Sendable {
    case ios
    case android
}

public enum Language: String, Hashable, Sendable {
    case swift
    case kotlin
    case cpp = "c++"
}

public struct PlatformBinding: Hashable, Sendable {
    public let platform: Platform
    public let language: Language

    public init(platform: Platform, language: Language) {
        self.platform = platform
        self.language = language
    }
}

public struct HybridObjectIR: Hashable, Sendable {
    public let className: String
    public let platforms: [PlatformBinding]
    public let methods: [MethodIR]
    public let sourceLocation: SourceLocationIR?

    public init(
        className: String,
        platforms: [PlatformBinding],
        methods: [MethodIR] = [],
        sourceLocation: SourceLocationIR? = nil
    ) {
        self.className = className
        self.platforms = platforms
        self.methods = methods
        self.sourceLocation = sourceLocation
    }

    /// The TS spec interface name. Convention: strip the `Hybrid` prefix from
    /// the impl class. e.g. `HybridMath` -> `Math`.
    public var specName: String {
        if className.hasPrefix("Hybrid") {
            return String(className.dropFirst("Hybrid".count))
        }
        return className
    }
}

public struct SourceLocationIR: Hashable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

public struct MethodIR: Hashable, Sendable {
    public let name: String
    public let parameters: [ParameterIR]
    public let returnType: TypeIR
    public let isThrowing: Bool

    public init(
        name: String,
        parameters: [ParameterIR],
        returnType: TypeIR,
        isThrowing: Bool
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.isThrowing = isThrowing
    }
}

public struct ParameterIR: Hashable, Sendable {
    public let label: String
    public let type: TypeIR

    public init(label: String, type: TypeIR) {
        self.label = label
        self.type = type
    }
}

/// Phase 1A scope: int/number-only primitives. String/array/struct/enum/etc.
/// are intentionally excluded — the extractor rejects them with a diagnostic.
public enum TypeIR: Hashable, Sendable {
    case int64
    case uint64
    case double
    case float
    case bool
    case void

    public var swiftSpelling: String {
        switch self {
        case .int64: return "Int64"
        case .uint64: return "UInt64"
        case .double: return "Double"
        case .float: return "Float"
        case .bool: return "Bool"
        case .void: return "Void"
        }
    }
}

public struct Diagnostic: Error, Hashable, Sendable, CustomStringConvertible {
    public let message: String
    public let location: SourceLocationIR?

    public init(message: String, location: SourceLocationIR? = nil) {
        self.message = message
        self.location = location
    }

    public var description: String {
        if let location {
            return "\(location.file):\(location.line):\(location.column): error: \(message)"
        }
        return "error: \(message)"
    }
}
