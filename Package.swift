// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "YarnJamBot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YarnJamBot",
            path: "Sources/YarnJamBot"
        )
    ]
)
