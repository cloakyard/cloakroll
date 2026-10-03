// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloakRollScaleProbe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/CloakRollCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .executableTarget(name: "ScaleProbe", dependencies: [
            .product(name: "MediaModels", package: "CloakRollCore"),
            .product(name: "MediaCatalog", package: "CloakRollCore"),
            .product(name: "BackupEngine", package: "CloakRollCore"),
            .product(name: "BackupPersistence", package: "CloakRollCore"),
            .product(name: "GRDB", package: "GRDB.swift")
        ])
    ]
)
