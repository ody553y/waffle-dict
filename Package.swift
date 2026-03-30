// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screamer",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ScreamerCore",
            targets: ["ScreamerCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "ScreamerCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "ScreamerApp",
            dependencies: [
                "ScreamerCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: [
                "Info.plist",
                "ScreamerApp.entitlements",
            ],
            resources: [
                .process("Localizable.xcstrings"),
            ]
        ),
        .testTarget(
            name: "ScreamerCoreTests",
            dependencies: ["ScreamerCore"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
