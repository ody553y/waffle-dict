// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screamer",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ScreamerCore",
            targets: ["ScreamerCore"]
        ),
    ],
    targets: [
        .target(
            name: "ScreamerCore"
        ),
        .executableTarget(
            name: "ScreamerApp",
            dependencies: ["ScreamerCore"]
        ),
        .testTarget(
            name: "ScreamerCoreTests",
            dependencies: ["ScreamerCore"]
        ),
    ]
)
