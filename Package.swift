// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DicyaninSceneMovement",
    platforms: [
        .visionOS(.v2),
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "DicyaninSceneMovement",
            targets: ["DicyaninSceneMovement"]
        )
    ],
    targets: [
        .target(
            name: "DicyaninSceneMovement"
        ),
        .testTarget(
            name: "DicyaninSceneMovementTests",
            dependencies: ["DicyaninSceneMovement"]
        )
    ]
)
