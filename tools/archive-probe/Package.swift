// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ArchiveProbe",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "ArchiveProbe", targets: ["ArchiveProbe"])],
    dependencies: [
        .package(url: "https://github.com/mtgto/Unrar.swift", exact: "0.5.4"),
        .package(url: "https://github.com/tsolomko/SWCompression", exact: "4.8.7"),
        .package(url: "https://github.com/OlehKulykov/PLzmaSDK.git", revision: "1b27a1c9df85805342d1b049427d6d1dc7ce713d")
    ],
    targets: [
        .target(name: "ArchiveProbe", dependencies: [
            .product(name: "Unrar", package: "Unrar.swift"),
            .product(name: "SWCompression", package: "SWCompression"),
            .product(name: "PLzmaSDK", package: "PLzmaSDK")
        ]),
        .testTarget(name: "ArchiveProbeTests", dependencies: ["ArchiveProbe"],
                    resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5]
)
