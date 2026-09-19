// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "BackupImportCheck",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/LegadoCore")],
    targets: [.executableTarget(name: "BackupImportCheck", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                               swiftSettings: [.swiftLanguageMode(.v5)])]
)
