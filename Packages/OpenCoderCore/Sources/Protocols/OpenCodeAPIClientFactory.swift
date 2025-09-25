import Dependencies
import Models

public struct OpenCodeAPIClientFactory: Sendable {
  public var make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol

  public init(make: @escaping @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol) {
    self.make = make
  }
}

public enum OpenCodeAPIClientFactoryKey: DependencyKey, Sendable {
  public static let liveValue = OpenCodeAPIClientFactory { _ in
    MockOpenCodeAPIClient()
  }
  public static let testValue = OpenCodeAPIClientFactory { _ in
    MockOpenCodeAPIClient()
  }
}

extension DependencyValues {
  public var openCodeAPIFactory: OpenCodeAPIClientFactory {
    get { self[OpenCodeAPIClientFactoryKey.self] }
    set { self[OpenCodeAPIClientFactoryKey.self] = newValue }
  }
}
