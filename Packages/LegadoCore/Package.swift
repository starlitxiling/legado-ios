// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LegadoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LegadoCore", targets: ["LegadoCore"])],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9")
    ],
    targets: [
        .target(name: "LegadoCore", dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LegadoCoreTests", dependencies: ["LegadoCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
