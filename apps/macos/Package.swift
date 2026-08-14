// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DeepSeekHarnessMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeepSeekHarness", targets: ["DeepSeekHarness"]),
        .library(name: "DshNativeProtocol", targets: ["DshNativeProtocol"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
    ],
    targets: [
        .target(name: "DshNativeProtocol"),
        .executableTarget(
            name: "DeepSeekHarness",
            dependencies: [
                "DshNativeProtocol",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "DshNativeProtocolTests",
            dependencies: ["DshNativeProtocol"]
        ),
        .testTarget(
            name: "DeepSeekHarnessTests",
            dependencies: ["DeepSeekHarness", "DshNativeProtocol"]
        ),
    ]
)
