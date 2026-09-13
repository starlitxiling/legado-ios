// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AppCoreCheck",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/LegadoCore")],
    targets: [
        .target(name: "ReaderCheck", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ReaderCheckTests", dependencies: ["ReaderCheck"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "SettingsBackupCheck", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SettingsBackupCheckTests", dependencies: ["SettingsBackupCheck"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "DatabaseLifecycleCheck", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DatabaseLifecycleCheckTests", dependencies: ["DatabaseLifecycleCheck"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "AppCoreCheck", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AppCoreCheckTests", dependencies: ["AppCoreCheck"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
