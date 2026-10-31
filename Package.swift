// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BreakLoop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "BreakLoop",
            targets: ["BreakLoop"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "BreakLoop",
            dependencies: [],
            path: "Sources/BreakLoop"
        ),
        .testTarget(
            name: "BreakLoopTests",
            dependencies: ["BreakLoop"],
            path: "Tests/BreakLoopTests"
        ),
    ]
)
