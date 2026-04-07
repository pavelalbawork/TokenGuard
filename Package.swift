// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageTool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "UsageTool",
            targets: ["UsageTool"]
        )
    ],
    targets: [
        .target(
            name: "UsageTool",
            path: "UsageTool",
            exclude: [
                "UsageToolApp.swift",
                "Views",
                "Resources"
            ]
        ),
        .testTarget(
            name: "UsageToolTests",
            dependencies: ["UsageTool"],
            path: "Tests/UsageToolTests"
        )
    ]
)
