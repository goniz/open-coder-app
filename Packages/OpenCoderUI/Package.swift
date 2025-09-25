// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenCoderUI",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "OpenCoderUI",
            targets: [
                "OpenCoderUI"
            ]
        )
    ],
    dependencies: [
        // Local dependency
        .package(path: "../OpenCoderCore"),
        
        // UI-specific
        .package(url: "https://github.com/exyte/Chat.git", from: "2.7.0"),
        
        // Re-export TCA for UI usage
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2"),
    ],
    targets: [
        // MARK: - UI Modules
         .target(
             name: "OpenCoderUI",
             dependencies: [
                 .product(name: "OpenCoderCore", package: "OpenCoderCore"),
                 .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                 .product(name: "ExyteChat", package: "Chat"),
             ],
             path: "Sources/Views",
             resources: [
                 .process("Resources")
             ]
         ),
    ]
)
