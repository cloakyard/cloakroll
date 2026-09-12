// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloakRollCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MediaModels", targets: ["MediaModels"]),
        .library(name: "MediaCatalog", targets: ["MediaCatalog"]),
        .library(name: "DeviceCapture", targets: ["DeviceCapture"]),
        .library(name: "ThumbnailPipeline", targets: ["ThumbnailPipeline"]),
        .library(name: "BackupEngine", targets: ["BackupEngine"]),
        .library(name: "BackupPersistence", targets: ["BackupPersistence"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(name: "MediaModels", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "MediaCatalog",
            dependencies: ["MediaModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DeviceCapture",
            dependencies: ["MediaModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(name: "ThumbnailPipeline", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "BackupEngine", dependencies: ["MediaModels"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "BackupPersistence",
            dependencies: ["MediaModels", "BackupEngine", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MediaModelsTests",
            dependencies: ["MediaModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MediaCatalogTests",
            dependencies: ["MediaCatalog"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DeviceCaptureTests",
            dependencies: ["DeviceCapture", "MediaModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ThumbnailPipelineTests",
            dependencies: ["ThumbnailPipeline"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BackupEngineTests",
            dependencies: ["BackupEngine", "MediaModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BackupPersistenceTests",
            dependencies: ["BackupPersistence", "BackupEngine", "MediaModels", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
