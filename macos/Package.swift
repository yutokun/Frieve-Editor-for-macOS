// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "macos",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FrieveEditorMac",
            targets: ["macos"]
        )
    ],
    targets: [
        .executableTarget(
            name: "macos",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "macosTests",
            dependencies: ["macos"]
        )
    ],
    swiftLanguageModes: [.v6]
)
