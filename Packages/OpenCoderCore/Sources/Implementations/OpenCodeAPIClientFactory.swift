import Dependencies
import Models
import Protocols

public struct OpenCodeAPIClientFactory: OpenCodeAPIClientFactoryProtocol {
  public let make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol

  public init(make: @escaping @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol) {
    self.make = make
  }

  public static let live = OpenCodeAPIClientFactory { config in
    Task { @MainActor in
      AppLogger.shared.log("Creating LiveOpenCodeAPIClient with config: \(config)", level: .info, category: .api)
    }
    let client = LiveOpenCodeAPIClient(configuration: config)
    Task { @MainActor in
      AppLogger.shared.log("Created live client: \(type(of: client))", level: .info, category: .api)
    }
    return client
  }
}
