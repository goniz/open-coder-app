// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenCoderCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "OpenCoderCore",
            targets: [
                "Models", 
                "Protocols", 
                "Implementations", 
                "Features", 
                "OpenAPIGenerated"
            ]
        )
    ],
    dependencies: [
        // TCA and Dependencies
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.4"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", exact: "1.3.3"),
        
        // Networking
        .package(url: "https://github.com/apple/swift-nio-ssh", from: "0.11.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-async-http-client", from: "1.0.0"),
    ],
    targets: [
        // MARK: - Core Modules
        .target(
            name: "Models",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "Protocols",
            dependencies: [
                "Models",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "Implementations",
            dependencies: [
                "Models",
                "Protocols",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIAsyncHTTPClient", package: "swift-openapi-async-http-client"),
            ]
        ),
        .target(
            name: "Features",
            dependencies: [
                "Models",
                "Protocols",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "OpenAPIGenerated",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        
        // MARK: - Test Targets
        .testTarget(
            name: "ModelsTests",
            dependencies: [
                "Models",
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .testTarget(
            name: "ProtocolsTests",
            dependencies: [
                "Protocols",
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .testTarget(
            name: "FeaturesTests",
            dependencies: [
                "Features",
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
    ]
)