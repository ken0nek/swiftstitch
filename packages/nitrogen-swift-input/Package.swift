// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "nitrogen-swift-input",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NitrogenSwiftInputCore", targets: ["NitrogenSwiftInputCore"]),
        .executable(name: "nitrogen-swift-input", targets: ["NitrogenSwiftInputCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.0"),
    ],
    targets: [
        .target(
            name: "NitrogenSwiftInputCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "NitrogenSwiftInputCLI",
            dependencies: ["NitrogenSwiftInputCore"]
        ),
        .testTarget(
            name: "NitrogenSwiftInputCoreTests",
            dependencies: ["NitrogenSwiftInputCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
