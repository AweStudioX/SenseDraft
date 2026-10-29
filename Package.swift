// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SenseDraft",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SenseDraftCore", targets: ["SenseDraftCore"]),
        .executable(name: "SenseDraftMac", targets: ["SenseDraftMac"])
    ],
    targets: [
        .target(name: "SenseDraftCore"),
        .executableTarget(name: "SenseDraftMac", dependencies: ["SenseDraftCore"]),
        .testTarget(name: "SenseDraftCoreTests", dependencies: ["SenseDraftCore"]),
        .testTarget(name: "SenseDraftMacTests", dependencies: ["SenseDraftMac", "SenseDraftCore"])
    ]
)
