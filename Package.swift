// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MinecraftHelper",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MinecraftHelper",
            path: "Sources/MinecraftHelper"
        )
    ]
)
