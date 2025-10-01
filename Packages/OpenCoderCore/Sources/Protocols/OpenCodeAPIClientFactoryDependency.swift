import Dependencies
import Models

public protocol OpenCodeAPIClientFactoryProtocol: Sendable {
  var make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol { get }
}

public enum OpenCodeAPIClientFactoryDependencyKey: DependencyKey, TestDependencyKey, Sendable {
  public static let liveValue: OpenCodeAPIClientFactoryProtocol = UnconfiguredFactory()
  public static let testValue: OpenCodeAPIClientFactoryProtocol = MockFactory()
}

public extension DependencyValues {
  var openCodeAPIFactory: OpenCodeAPIClientFactoryProtocol {
    get { self[OpenCodeAPIClientFactoryDependencyKey.self] }
    set { self[OpenCodeAPIClientFactoryDependencyKey.self] = newValue }
  }
}

private struct UnconfiguredFactory: OpenCodeAPIClientFactoryProtocol {
  let make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol = { _ in
    Task {
      await AppLogger.shared.log(
        "ERROR: OpenCodeAPIClientFactory dependency not configured properly",
        level: .error,
        category: .api
      )
    }
    fatalError(
      "OpenCodeAPIClientFactory dependency must be explicitly set. Use OpenCodeAPIClientFactory.live in production."
    )
  }
}

private struct MockFactory: OpenCodeAPIClientFactoryProtocol {
  let make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol = { _ in
    return MockOpenCodeAPIClient()
  }
}
