// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ArchiveProbe",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "ArchiveProbe", targets: ["ArchiveProbe"])],
    dependencies: [
        .package(url: "https://github.com/mtgto/Unrar.swift", exact: "0.5.4"),
        .package(url: "https://github.com/tsolomko/SWCompression", exact: "4.8.7")
    ],
    targets: [
        .target(name: "ArchiveProbe", dependencies: [
            .product(name: "Unrar", package: "Unrar.swift"),
            .product(name: "SWCompression", package: "SWCompression")
        ]),
        .testTarget(name: "ArchiveProbeTests", dependencies: ["ArchiveProbe"],
                    resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
