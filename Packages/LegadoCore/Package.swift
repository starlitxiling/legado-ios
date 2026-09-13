// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LegadoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LegadoCore", targets: ["LegadoCore"])],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9"),
        .package(url: "https://github.com/tid-kijyun/Kanna.git", exact: "6.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(name: "LegadoCore", dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup"),
                                                  .product(name: "Kanna", package: "Kanna"),
                                                  .product(name: "GRDB", package: "GRDB.swift")],
                exclude: ["Resources"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LegadoCoreTests", dependencies: ["LegadoCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
