import Foundation
import Testing
@testable import NitrogenSwiftEmbeddedCore
@testable import NitrogenSwiftInputCore

private func loadGolden(_ name: String) throws -> String {
    let url = Bundle.module.url(forResource: name, withExtension: "golden", subdirectory: "Fixtures")
    #expect(url != nil, "missing fixture \(name).golden")
    return try String(contentsOf: url!, encoding: .utf8)
}

@Suite struct CppGlueEmitterTests {
    @Test func hybridSimpleMath_matchesGolden() throws {
        let ir = HybridObjectIR(
            className: "HybridSimpleMath",
            platforms: [PlatformBinding(platform: .android, language: .swift)],
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
        let actual = try CppGlueEmitter.emit(ir, namespace: "margelo::nitro::test")
        let golden = try loadGolden("HybridSimpleMath.hpp")
        #expect(actual == golden)
    }

    @Test func float_widens_to_double_in_cpp_signature_and_round_trips_via_static_cast() throws {
        let ir = HybridObjectIR(
            className: "HybridF",
            platforms: [PlatformBinding(platform: .android, language: .swift)],
            methods: [
                MethodIR(
                    name: "passFloat",
                    parameters: [ParameterIR(label: "value", type: .float)],
                    returnType: .float,
                    isThrowing: false
                ),
            ]
        )
        let cpp = try CppGlueEmitter.emit(ir, namespace: "ns")
        // C++ override signature widens to double.
        #expect(cpp.contains("double passFloat(double value) override"))
        // extern "C" decl uses C `float` to match the @c bridge.
        #expect(cpp.contains("extern float HybridF_passFloat(void* handle, float value);"))
        // Body casts argument to float, return value back to double.
        #expect(cpp.contains("return static_cast<double>(HybridF_passFloat(_handle, static_cast<float>(value)));"))
    }

    @Test func void_method_uses_no_return() throws {
        let ir = HybridObjectIR(
            className: "HybridV",
            platforms: [PlatformBinding(platform: .android, language: .swift)],
            methods: [
                MethodIR(
                    name: "reset",
                    parameters: [],
                    returnType: .void,
                    isThrowing: false
                ),
            ]
        )
        let cpp = try CppGlueEmitter.emit(ir, namespace: "ns")
        #expect(cpp.contains("void reset() override"))
        #expect(cpp.contains("HybridV_reset(_handle);"))
        // No return on a void method.
        #expect(!cpp.contains("return HybridV_reset"))
    }

    @Test func consolidated_cpp17_namespace_form() throws {
        let ir = HybridObjectIR(
            className: "HybridX",
            platforms: [PlatformBinding(platform: .android, language: .swift)],
            methods: []
        )
        let cpp = try CppGlueEmitter.emit(ir, namespace: "a::b::c")
        // C++17 consolidated form, matching nitrogen's existing emitters.
        #expect(cpp.contains("namespace a::b::c {"))
        #expect(cpp.contains("} // namespace a::b::c"))
    }
}
