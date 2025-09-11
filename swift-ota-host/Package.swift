// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-ota-host",
    platforms: [.macOS(.v13), .iOS(.v13)],
    products: [
        .executable(name: "swift-ota-host", targets: ["swift-ota-host"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "swift-ota-host",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)