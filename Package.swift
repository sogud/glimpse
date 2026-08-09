// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhotoSortSessionCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PhotoSortSessionCore", targets: ["PhotoSortSessionCore"]),
        .library(name: "PhotoSortSmartCore", targets: ["PhotoSortSmartCore"])
    ],
    targets: [
        .target(
            name: "PhotoSortSessionCore",
            path: "Sources/Model",
            exclude: [
                "PhotoAsset.swift",
                "SmartAnalysisModels.swift"
            ],
            sources: [
                "CleanupSession.swift",
                "CleanupSessionRestore.swift"
            ]
        ),
        .testTarget(
            name: "PhotoSortSessionCoreTests",
            dependencies: ["PhotoSortSessionCore"],
            path: "Tests/PhotoSortSessionCoreTests"
        ),
        .target(
            name: "PhotoSortSmartCore",
            path: "Sources/SmartCore"
        ),
        .testTarget(
            name: "PhotoSortSmartCoreTests",
            dependencies: ["PhotoSortSmartCore"],
            path: "Tests/PhotoSortSmartCoreTests"
        )
    ]
)
