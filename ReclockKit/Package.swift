// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ReclockKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ReclockKit", targets: ["ReclockKit"])
    ],
    targets: [
        .target(
            name: "ReclockKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ReclockKitTests",
            dependencies: ["ReclockKit"]
        ),
    ]
)
