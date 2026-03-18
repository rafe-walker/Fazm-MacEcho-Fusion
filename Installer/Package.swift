// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FazmInstaller",
    platforms: [
        .macOS("14.0")
    ],
    targets: [
        .executableTarget(
            name: "FazmInstaller",
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        )
    ]
)
