import Foundation
import Testing
@testable import NitrogenSwiftEmbeddedCore
@testable import NitrogenSwiftInputCore

private func loadGolden(_ name: String) throws -> String {
    let url = Bundle.module.url(forResource: name, withExtension: "golden", subdirectory: "Fixtures")
    #expect(url != nil, "missing fixture \(name).golden")
    return try String(contentsOf: url!, encoding: .utf8)
}

private func makeIR(
    className: String,
    methods: [MethodIR]
) -> HybridObjectIR {
    HybridObjectIR(
        className: className,
        platforms: [PlatformBinding(platform: .android, language: .swift)],
        methods: methods
    )
}

@Suite struct CBridgeEmitterTests {
    @Test func hybridSimpleMath_matchesGolden() throws {
        let ir = makeIR(
            className: "HybridSimpleMath",
            methods: [
                MethodIR(
                    name: "add",
                    parameters: [
                        ParameterIR(label: "a", type: .double),
                        ParameterIR(label: "b", type: .double),
                    ],
                    returnType: .double,
                    isThrowing: false
                ),
                MethodIR(
                    name: "subtract",
                    parameters: [
                        ParameterIR(label: "a", type: .int64),
                        ParameterIR(label: "b", type: .int64),
                    ],
                    returnType: .int64,
                    isThrowing: false
                ),
            ]
        )
        let actual = try CBridgeEmitter.emit(ir)
        let golden = try loadGolden("HybridSimpleMath.swift")
        #expect(actual == golden)
    }

    @Test func hybridMath_matchesGolden_withThrowingMethod() throws {
        let ir = makeIR(
            className: "HybridMath",
            methods: [
                MethodIR(
                    name: "add",
                    parameters: [
                        ParameterIR(label: "a", type: .double),
                        ParameterIR(label: "b", type: .double),
                    ],
                    returnType: .double,
                    isThrowing: true
                ),
                MethodIR(
                    name: "subtract",
                    parameters: [
                        ParameterIR(label: "a", type: .int64),
                        ParameterIR(label: "b", type: .int64),
                    ],
                    returnType: .int64,
                    isThrowing: false
                ),
                MethodIR(
                    name: "magnitude",
                    parameters: [
                        ParameterIR(label: "value", type: .int64),
                    ],
                    returnType: .uint64,
                    isThrowing: false
                ),
                MethodIR(
                    name: "reset",
                    parameters: [],
                    returnType: .void,
                    isThrowing: false
                ),
            ]
        )
        let actual = try CBridgeEmitter.emit(ir)
        let golden = try loadGolden("HybridMath.swift")
        #expect(actual == golden)
    }

    @Test func hybridTypes_fullTypeMatrix() throws {
        let ir = makeIR(
            className: "HybridTypes",
            methods: [
                MethodIR(name: "passBool", parameters: [ParameterIR(label: "value", type: .bool)], returnType: .bool, isThrowing: false),
                MethodIR(name: "passDouble", parameters: [ParameterIR(label: "value", type: .double)], returnType: .double, isThrowing: false),
                MethodIR(name: "passFloat", parameters: [ParameterIR(label: "value", type: .float)], returnType: .float, isThrowing: false),
                MethodIR(name: "passInt64", parameters: [ParameterIR(label: "value", type: .int64)], returnType: .int64, isThrowing: false),
                MethodIR(name: "passUInt64", parameters: [ParameterIR(label: "value", type: .uint64)], returnType: .uint64, isThrowing: false),
                MethodIR(name: "returnsVoid", parameters: [], returnType: .void, isThrowing: false),
                MethodIR(name: "explicitVoid", parameters: [], returnType: .void, isThrowing: false),
                MethodIR(name: "throwingAdd", parameters: [
                    ParameterIR(label: "a", type: .double),
                    ParameterIR(label: "b", type: .double),
                ], returnType: .double, isThrowing: true),
                MethodIR(name: "noArgs", parameters: [], returnType: .int64, isThrowing: false),
            ]
        )
        let actual = try CBridgeEmitter.emit(ir)
        let golden = try loadGolden("HybridTypes.swift")
        #expect(actual == golden)
    }

    @Test func emit_isDeterministic() throws {
        let ir = makeIR(
            className: "HybridSimpleMath",
            methods: [
                MethodIR(
                    name: "add",
                    parameters: [
                        ParameterIR(label: "a", type: .double),
                        ParameterIR(label: "b", type: .double),
                    ],
                    returnType: .double,
                    isThrowing: false
                ),
            ]
        )
        let first = try CBridgeEmitter.emit(ir)
        let second = try CBridgeEmitter.emit(ir)
        #expect(first == second)
    }
}
