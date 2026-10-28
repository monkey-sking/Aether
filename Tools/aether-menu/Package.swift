// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "aether-menu",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "aether-menu", targets: ["AetherMenuCLI"]),
        .library(name: "AetherMenuKit", targets: ["AetherMenuKit"]),
    ],
    targets: [
        .target(
            name: "AetherMenuKit",
            path: "Sources/AetherMenuKit"
        ),
        .executableTarget(
            name: "AetherMenuCLI",
            dependencies: ["AetherMenuKit"],
            path: "Sources/AetherMenuCLI"
        ),
        .testTarget(
            name: "AetherMenuTests",
            dependencies: ["AetherMenuKit"],
            path: "Tests/AetherMenuTests"
        ),
    ]
)
