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
  ],
  targets: [
    // Empty integration test target if needed in the future
    .testTarget(
      name: "IntegrationTests",
      dependencies: [
        .product(name: "OpenCoderCore", package: "OpenCoderCore"),
        .product(name: "OpenCoderUI", package: "OpenCoderUI"),
        .product(name: "OpenCoderApp", package: "OpenCoderApp"),
      ]
    )
  ]
)


