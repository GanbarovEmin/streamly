// swift-tools-version: 5.9

import PackageDescription

let arm64OnlySwiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-target", "arm64-apple-macosx13.0"], .when(platforms: [.macOS]))
]

let package = Package(
    name: "CineFlow",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CineFlow", targets: ["CineFlowApp"]),
        .library(name: "CineFlowCore", targets: ["CineFlowCore"]),
        .library(name: "CineFlowLocalization", targets: ["CineFlowLocalization"]),
        .library(name: "CineFlowDesignSystem", targets: ["CineFlowDesignSystem"]),
        .library(name: "CineFlowUI", targets: ["CineFlowUI"]),
        .library(name: "CineFlowDatabase", targets: ["CineFlowDatabase"]),
        .library(name: "CineFlowMetadata", targets: ["CineFlowMetadata"]),
        .library(name: "CineFlowTorrent", targets: ["CineFlowTorrent"]),
        .library(name: "CineFlowPlayback", targets: ["CineFlowPlayback"]),
        .library(name: "CineFlowSubtitles", targets: ["CineFlowSubtitles"]),
        .library(name: "CineFlowSources", targets: ["CineFlowSources"]),
        .library(name: "CineFlowSettings", targets: ["CineFlowSettings"]),
        .library(name: "CineFlowUpdater", targets: ["CineFlowUpdater"]),
        .library(name: "CineFlowDiagnostics", targets: ["CineFlowDiagnostics"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "CineFlowApp",
            dependencies: [
                "CineFlowCore",
                "CineFlowLocalization",
                "CineFlowUI",
                "CineFlowDatabase",
                "CineFlowMetadata",
                "CineFlowTorrent",
                "CineFlowPlayback",
                "CineFlowSubtitles",
                "CineFlowSources",
                "CineFlowSettings",
                "CineFlowUpdater",
                "CineFlowDiagnostics"
            ],
            swiftSettings: arm64OnlySwiftSettings
        ),
        .target(name: "CineFlowCore", swiftSettings: arm64OnlySwiftSettings),
        .target(
            name: "CineFlowLocalization",
            resources: [.process("Resources")],
            swiftSettings: arm64OnlySwiftSettings
        ),
        .target(name: "CineFlowDesignSystem", dependencies: ["CineFlowLocalization"], swiftSettings: arm64OnlySwiftSettings),
        .target(name: "CineFlowUI", dependencies: ["CineFlowCore", "CineFlowDesignSystem", "CineFlowLocalization", "CineFlowPlayback", "CineFlowSources", "CineFlowSubtitles"], swiftSettings: arm64OnlySwiftSettings),
        .target(
            name: "CineFlowDatabase",
            dependencies: [
                "CineFlowCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: arm64OnlySwiftSettings
        ),
        .target(name: "CineFlowMetadata", dependencies: ["CineFlowCore", "CineFlowDatabase"], swiftSettings: arm64OnlySwiftSettings),
        .target(name: "CineFlowTorrent", dependencies: ["CineFlowCore"], swiftSettings: arm64OnlySwiftSettings),
        .target(name: "CineFlowPlayback", dependencies: ["CineFlowCore"], swiftSettings: arm64OnlySwiftSettings),
        .target(name: "CineFlowSubtitles", dependencies: ["CineFlowCore"], swiftSettings: arm64OnlySwiftSettings),
        .target(name: "CineFlowSources", dependencies: ["CineFlowCore"], swiftSettings: arm64OnlySwiftSettings),
        .target(name: "CineFlowSettings", dependencies: ["CineFlowCore"], swiftSettings: arm64OnlySwiftSettings),
        .target(
            name: "CineFlowUpdater",
            dependencies: [
                "CineFlowCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            swiftSettings: arm64OnlySwiftSettings
        ),
        .target(name: "CineFlowDiagnostics", dependencies: ["CineFlowCore"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(name: "CineFlowCoreTests", dependencies: ["CineFlowCore"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(name: "CineFlowLocalizationTests", dependencies: ["CineFlowLocalization"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(name: "CineFlowDesignSystemTests", dependencies: ["CineFlowDesignSystem", "CineFlowLocalization"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(name: "CineFlowMetadataTests", dependencies: ["CineFlowMetadata", "CineFlowDatabase"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(name: "CineFlowPlaybackTests", dependencies: ["CineFlowPlayback"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(name: "CineFlowSourcesTests", dependencies: ["CineFlowSources"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(name: "CineFlowSubtitlesTests", dependencies: ["CineFlowSubtitles"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(name: "CineFlowTorrentTests", dependencies: ["CineFlowTorrent"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(name: "CineFlowUITests", dependencies: ["CineFlowUI", "CineFlowSources", "CineFlowSubtitles"], swiftSettings: arm64OnlySwiftSettings),
        .testTarget(
            name: "CineFlowDependencyTests",
            dependencies: [
                "CineFlowCore",
                "CineFlowDatabase",
                "CineFlowMetadata",
                "CineFlowTorrent",
                "CineFlowPlayback",
                "CineFlowSubtitles",
                "CineFlowSources",
                "CineFlowSettings",
                "CineFlowUpdater",
                "CineFlowDiagnostics"
            ],
            swiftSettings: arm64OnlySwiftSettings
        ),
        .testTarget(
            name: "CineFlowDatabaseTests",
            dependencies: [
                "CineFlowCore",
                "CineFlowDatabase",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            swiftSettings: arm64OnlySwiftSettings
        )
    ]
)
