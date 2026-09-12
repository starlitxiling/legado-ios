// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LegadoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "LegadoCore", targets: ["LegadoCore"])],
    targets: [
        .target(name: "LegadoCore"),
        .testTarget(name: "LegadoCoreTests", dependencies: ["LegadoCore"])
    ]
)
