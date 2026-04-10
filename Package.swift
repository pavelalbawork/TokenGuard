// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenGuard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TokenGuard",
            targets: ["TokenGuard"]
        )
    ],
    targets: [
        .target(
            name: "TokenGuard",
            path: "TokenGuard",
            exclude: [
                "TokenGuardApp.swift",
                "Views",
                "Resources"
            ]
        ),
        .testTarget(
            name: "TokenGuardTests",
            dependencies: ["TokenGuard"],
            path: "Tests/TokenGuardTests"
        )
    ]
)
