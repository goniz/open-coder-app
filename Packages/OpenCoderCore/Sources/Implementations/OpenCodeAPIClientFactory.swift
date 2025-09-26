import Dependencies
import Models
import Protocols

public struct OpenCodeAPIClientFactory: OpenCodeAPIClientFactoryProtocol {
  public let make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol

  public init(make: @escaping @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol) {
    self.make = make
  }

  public static let live = OpenCodeAPIClientFactory { config in
    return LiveOpenCodeAPIClient(configuration: config)
  }
}
