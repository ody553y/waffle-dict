// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Waffle",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "WaffleCore",
            targets: ["WaffleCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "WaffleCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "WaffleApp",
            dependencies: [
                "WaffleCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: [
                "Info.plist",
                "WaffleApp.entitlements",
            ],
            resources: [
                .process("Localizable.xcstrings"),
            ]
        ),
        .testTarget(
            name: "WaffleCoreTests",
            dependencies: ["WaffleCore"],
            resources: [
                .process("Fixtures"),
            ]
        ),
        .testTarget(
            name: "WaffleAppTests",
            dependencies: [
                "WaffleApp",
                "WaffleCore",
            ]
        ),
    ]
)
