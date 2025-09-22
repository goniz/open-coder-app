// swift-tools-version: 6.0

import Foundation
import PackageDescription

let appName = "OpenCoderApp"

// MARK: - Third party dependencies

let tca = SourceControlDependency(
  package: .package(
    url: "https://github.com/pointfreeco/swift-composable-architecture",
    from: "1.22.2"
  ),
  productName: "ComposableArchitecture"
)
let swiftDependencies = Package.Dependency.package(
  url: "https://github.com/pointfreeco/swift-dependencies",
  from: "1.9.4"
)
let dependencies = SourceControlDependency(
  package: swiftDependencies,
  productName: "Dependencies"
)
let dependenciesMacros = SourceControlDependency(
  package: swiftDependencies,
  productName: "DependenciesMacros"
)
let customDump = SourceControlDependency(
  package: .package(
    url: "https://github.com/pointfreeco/swift-custom-dump",
    exact: "1.3.3"
  ),
  productName: "CustomDump"
)
let swiftNIOSSH = SourceControlDependency(
  package: .package(
    url: "https://github.com/apple/swift-nio-ssh",
    from: "0.11.0"
  ),
  productName: "NIOSSH"
)
let swiftOpenAPIGenerator = SourceControlDependency(
  package: .package(
    url: "https://github.com/apple/swift-openapi-generator",
    from: "1.0.0"
  ),
  productName: "OpenAPIGenerator"
)
let swiftOpenAPIRuntime = SourceControlDependency(
  package: .package(
    url: "https://github.com/apple/swift-openapi-runtime",
    from: "1.0.0"
  ),
  productName: "OpenAPIRuntime"
)
let swiftOpenAPITransport = SourceControlDependency(
  package: .package(
    url: "https://github.com/swift-server/swift-openapi-async-http-client",
    from: "1.0.0"
  ),
  productName: "OpenAPIAsyncHTTPClient"
)
let exyteChat = SourceControlDependency(
  package: .package(
    url: "https://github.com/exyte/Chat.git",
    from: "2.6.9"
  ),
  productName: "ExyteChat"
)

// MARK: - Modules. Ordered by dependency hierarchy.

let models = SingleTargetLibrary(
  name: "Models",
  dependencies: []
)
let openAPIGenerated = SingleTargetLibrary(
  name: "OpenAPIGenerated",
  dependencies: [
    swiftOpenAPIRuntime.targetDependency,
  ],
  plugins: [
    .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
  ]
)
let dependencyClients = SingleTargetLibrary(
  name: "DependencyClients",
  dependencies: [
    tca.targetDependency,
    dependencies.targetDependency,
    dependenciesMacros.targetDependency,
    models.targetDependency,
    swiftNIOSSH.targetDependency,
    swiftOpenAPIRuntime.targetDependency,
    openAPIGenerated.targetDependency,
  ]
)
let features = SingleTargetLibrary(
  name: "Features",
  dependencies: [
    tca.targetDependency,
    models.targetDependency,
    dependencyClients.targetDependency,
    swiftNIOSSH.targetDependency,
    exyteChat.targetDependency,
  ]
)
let views = SingleTargetLibrary(
  name: "Views",
  dependencies: [
    tca.targetDependency,
    models.targetDependency,
    features.targetDependency,
    exyteChat.targetDependency,
  ],
  resources: [
    .process("Resources")
  ]
)
let dependencyClientsLive = SingleTargetLibrary(
  name: "DependencyClientsLive",
  dependencies: [
    dependencies.targetDependency,
    dependenciesMacros.targetDependency,
    dependencyClients.targetDependency,
    openAPIGenerated.targetDependency,
    swiftOpenAPITransport.targetDependency,
  ]
)
let openCoder = SingleTargetLibrary(
  name: "OpenCoderLib",
  dependencies: [
    features.targetDependency,
    views.targetDependency,
    dependencyClientsLive.targetDependency,
  ]
)

// MARK: - Package manifest

let package = Package(
  name: appName + "Package",  // To avoid target name collision when importing to Xcode project
  defaultLocalization: "en",
  platforms: [
    .iOS(.v17),
    .macOS(.v15),
  ],
  products: [
    dependencyClients.product,
    dependencyClientsLive.product,
    features.product,
    models.product,
    openAPIGenerated.product,
    openCoder.product,
    views.product,
  ],
  dependencies: [
    tca.package,
    swiftDependencies,
    customDump.package,
    swiftNIOSSH.package,
    swiftOpenAPIGenerator.package,
    swiftOpenAPIRuntime.package,
    swiftOpenAPITransport.package,
    exyteChat.package,
  ],
  targets: [
    dependencyClients.target,
    dependencyClients.testTarget,
    dependencyClientsLive.target,
    features.target,
    features.testTarget,
    models.target,
    models.testTarget,
    openAPIGenerated.target,
    openCoder.target,
    views.target,
    views.testTarget,
  ]
)

// MARK: - Helpers

/// Third party dependencies.
struct SourceControlDependency {
  var package: Package.Dependency
  var productName: String
  var condition: TargetDependencyCondition?

  init(
    package: Package.Dependency,
    productName: String,
    condition: TargetDependencyCondition? = nil
  ) {
    self.package = package
    self.productName = productName
    self.condition = condition
  }

  var targetDependency: Target.Dependency {
    var packageName: String

    switch package.kind {
    case let .fileSystem(name: name, path: path):
      guard let name = name ?? URL(string: path)?.lastPathComponent else {
        fatalError("No package name found. Path: \(path)")
      }
      packageName = name
    case let .sourceControl(name: name, location: location, _):
      guard let name = name ?? URL(string: location)?.lastPathComponent else {
        fatalError("No package name found. Location: \(location)")
      }
      packageName = name
      if packageName.hasSuffix(".git") {
        packageName.removeLast(4)
      }
    default:
      fatalError("Unsupported dependency kind: \(package.kind)")
    }

    return .product(name: productName, package: packageName, moduleAliases: nil, condition: condition)
  }
}

/// Local modules.
@MainActor
struct SingleTargetLibrary {
  var name: String
  var dependencies: [Target.Dependency] = []
  var resources: [Resource]? = nil
  var plugins: [Target.PluginUsage] = []

  var product: Product {
    .library(name: name, targets: [name])
  }

  var target: Target {
    if let resources = resources {
      return .target(name: name, dependencies: dependencies, resources: resources, plugins: plugins)
    } else {
      return .target(name: name, dependencies: dependencies, plugins: plugins)
    }
  }

  var targetDependency: Target.Dependency {
    .target(name: name)
  }

  var testTarget: Target {
    var deps: [Target.Dependency] = [targetDependency, customDump.targetDependency]
    if name == "DependencyClients" {
      deps.append(models.targetDependency)
    }
    return .testTarget(
      name: name + "Tests", dependencies: deps, plugins: plugins)
  }
}
