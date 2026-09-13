// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "WebBookSmoke",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/LegadoCore")],
    targets: [
        .executableTarget(name: "WebBookSmoke", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "WebBookSmokeTests", dependencies: ["WebBookSmoke"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
