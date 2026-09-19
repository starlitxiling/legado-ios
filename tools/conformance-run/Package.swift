// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ConformanceRun",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "conformance-run", targets: ["ConformanceRun"])],
    dependencies: [.package(path: "../../Packages/LegadoCore")],
    targets: [.executableTarget(name: "ConformanceRun", dependencies: [.product(name: "LegadoCore", package: "LegadoCore")],
                               swiftSettings: [.swiftLanguageMode(.v5)])]
)
