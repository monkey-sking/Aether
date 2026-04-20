// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RemoteProtocol",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "RemoteProtocol", targets: ["RemoteProtocol"])
    ],
    targets: [
        .target(name: "RemoteProtocol"),
        .testTarget(name: "RemoteProtocolTests", dependencies: ["RemoteProtocol"])
    ]
)
