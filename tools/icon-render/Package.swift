// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "IconRender",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "IconRenderer", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "IconRender", dependencies: ["IconRenderer"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "IconRendererTests", dependencies: ["IconRenderer"], resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
