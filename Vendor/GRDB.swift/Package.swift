// swift-tools-version:5.9

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .define("SQLITE_ENABLE_FTS5"),
    .define("SQLITE_ENABLE_SNAPSHOT"),
]

let package = Package(
    name: "GRDB",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v7),
    ],
    products: [
        .library(name: "GRDBSQLite", targets: ["GRDBSQLite"]),
        .library(name: "GRDB", targets: ["GRDB"]),
    ],
    targets: [
        .systemLibrary(
            name: "GRDBSQLite",
            providers: [.apt(["libsqlite3-dev"])]),
        .target(
            name: "GRDB",
            dependencies: [
                .target(name: "GRDBSQLite"),
            ],
            path: "GRDB",
            resources: [.copy("PrivacyInfo.xcprivacy")],
            swiftSettings: swiftSettings)
    ]
)
