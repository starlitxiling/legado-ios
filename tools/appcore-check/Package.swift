// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AppCoreCheck",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/LegadoCore")],
    targets: [
        .testTarget(name: "SourceLoginReviewCoreTests", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "SourceLoginCheck", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "SourceLoginCheckTests", dependencies: ["SourceLoginCheck"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "LocalImportCheck", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LocalImportCheckTests", dependencies: ["LocalImportCheck"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "ExploreImagesCheck", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ExploreImagesCheckTests", dependencies: ["ExploreImagesCheck"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
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
