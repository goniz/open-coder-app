// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenCoderApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "OpenCoderApp",
            targets: ["OpenCoderApp"]
        )
    ],
    dependencies: [
        // Local dependencies
        .package(path: "../OpenCoderCore"),
        .package(path: "../OpenCoderUI"),
        
        // TCA for app configuration
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2"),
    ],
    targets: [
        // MARK: - App Module
        .target(
            name: "OpenCoderApp",
            dependencies: [
                .product(name: "OpenCoderCore", package: "OpenCoderCore"),
                .product(name: "OpenCoderUI", package: "OpenCoderUI"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
        
        // MARK: - Test Targets
        .testTarget(
            name: "OpenCoderAppTests",
            dependencies: [
                "OpenCoderApp",
            ]
        ),
    ]
)