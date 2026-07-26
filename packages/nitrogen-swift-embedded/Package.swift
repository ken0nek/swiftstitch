// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "nitrogen-swift-embedded",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NitrogenSwiftEmbeddedCore", targets: ["NitrogenSwiftEmbeddedCore"]),
        .executable(name: "nitrogen-swift-embedded", targets: ["NitrogenSwiftEmbeddedCLI"]),
    ],
    dependencies: [
        .package(path: "../nitrogen-swift-input"),
    ],
    targets: [
        .target(
            name: "NitrogenSwiftEmbeddedCore",
            dependencies: [
                .product(name: "NitrogenSwiftInputCore", package: "nitrogen-swift-input"),
            ]
        ),
        .executableTarget(
            name: "NitrogenSwiftEmbeddedCLI",
            dependencies: ["NitrogenSwiftEmbeddedCore"]
        ),
        .testTarget(
            name: "NitrogenSwiftEmbeddedCoreTests",
            dependencies: ["NitrogenSwiftEmbeddedCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
