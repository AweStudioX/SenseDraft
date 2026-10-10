// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SenseDraft",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SenseDraftCore", targets: ["SenseDraftCore"])
    ],
    targets: [
        .target(name: "SenseDraftCore"),
        .testTarget(name: "SenseDraftCoreTests", dependencies: ["SenseDraftCore"])
    ]
)
