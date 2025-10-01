// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenCoderCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "OpenCoderCore",
            targets: [
                "OpenCoderCore"
            ]
        )
    ],
      dependencies: [
          // TCA and Dependencies
          .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.3"),
          .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.4"),
          .package(url: "https://github.com/pointfreeco/swift-custom-dump", exact: "1.3.3"),

           // Networking
           .package(url: "https://github.com/apple/swift-nio", from: "2.86.0"),
           .package(url: "https://github.com/apple/swift-nio-ssh", from: "0.11.0"),
           .package(url: "https://github.com/apple/swift-atomics", from: "1.3.0"),
           .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
           .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
           .package(url: "https://github.com/swift-server/swift-openapi-async-http-client", from: "1.0.0"),
           .package(url: "https://github.com/apple/swift-http-types", from: "1.4.0"),
           .package(url: "https://github.com/apple/swift-crypto", from: "3.15.0"),
      ],
    targets: [
        // MARK: - Core Modules
        .target(
            name: "OpenCoderCore",
            dependencies: [
                "Models",
                "Protocols",
                "Implementations",
                "Features",
                "OpenAPIGenerated"
            ]
        ),
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
                  "OpenAPIGenerated",
                  .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                  .product(name: "Dependencies", package: "swift-dependencies"),
                  .product(name: "Atomics", package: "swift-atomics"),
                  .product(name: "NIOCore", package: "swift-nio"),
                  .product(name: "NIOPosix", package: "swift-nio"),
                  .product(name: "NIOFoundationCompat", package: "swift-nio"),
                  .product(name: "HTTPTypes", package: "swift-http-types"),
                  .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                  .product(name: "NIOSSH", package: "swift-nio-ssh"),
                  .product(name: "Crypto", package: "swift-crypto"),
              ]
          ),
          .target(
              name: "Implementations",
              dependencies: [
                  "Models",
                  "Protocols",
                  "OpenAPIGenerated",
                  .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                  .product(name: "Dependencies", package: "swift-dependencies"),
                  .product(name: "NIOSSH", package: "swift-nio-ssh"),
                  .product(name: "Atomics", package: "swift-atomics"),
                  .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                  .product(name: "OpenAPIAsyncHTTPClient", package: "swift-openapi-async-http-client"),
              ]
          ),
          .target(
              name: "Features",
              dependencies: [
                  "Models",
                  "Protocols",
                  "Implementations",
                  "OpenAPIGenerated",
                  .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                  .product(name: "Dependencies", package: "swift-dependencies"),
                  .product(name: "HTTPTypes", package: "swift-http-types"),
                  .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                  .product(name: "NIOSSH", package: "swift-nio-ssh"),
                  .product(name: "Crypto", package: "swift-crypto"),
                  .product(name: "NIOFoundationCompat", package: "swift-nio"),
              ]
          ),
        .target(
            name: "OpenAPIGenerated",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            exclude: [
                "openapi.yaml",
                "openapi-generator-config.yaml"
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
            name: "ImplementationsTests",
            dependencies: [
                "Models",
                "Protocols", 
                "Implementations",
                .product(name: "CustomDump", package: "swift-custom-dump"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "Crypto", package: "swift-crypto"),
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
