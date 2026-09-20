// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChidiCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ChidiCore", targets: ["ChidiCore"])],
    targets: [
        .target(name: "ChidiCore", path: "manager/Core"),
        .testTarget(name: "ChidiCoreTests", dependencies: ["ChidiCore"])
    ]
)
