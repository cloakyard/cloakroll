// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloakRollCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MediaModels", targets: ["MediaModels"]),
        .library(name: "MediaCatalog", targets: ["MediaCatalog"])
    ],
    targets: [
        .target(name: "MediaModels", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "MediaCatalog",
            dependencies: ["MediaModels"],
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
        )
    ]
)
