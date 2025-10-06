// swift-tools-version: 6.0

import Foundation
import PackageDescription

// MARK: - Root package for integration tests only
// All app functionality has been moved to Packages/OpenCoderCore, OpenCoderUI, and OpenCoderApp

let package = Package(
  name: "OpenCoderAppRootPackage",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v17)
  ],
  products: [
    // No products - all functionality is in the packages
  ],
  dependencies: [
    // Local package dependencies for integration testing
    .package(path: "./Packages/OpenCoderCore"),
    .package(path: "./Packages/OpenCoderUI"),
    .package(path: "./Packages/OpenCoderApp"),
    
    // Third-party dependencies shared across packages/tests
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.2"),

    // OpenAPI Generator for code generation
    .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
  ],
  targets: [
    // Empty integration test target if needed in the future
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        .product(name: "OpenCoderCore", package: "OpenCoderCore"),
        .product(name: "OpenCoderUI", package: "OpenCoderUI"),
        .product(name: "OpenCoderApp", package: "OpenCoderApp"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
  ]
)

