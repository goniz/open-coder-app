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
        "WARNING: Using mock factory because dependency not configured",
        level: .warning,
        category: .api
      )
    }
    return MockOpenCodeAPIClient()
  }
}

private struct MockFactory: OpenCodeAPIClientFactoryProtocol {
  let make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol = { _ in
    return MockOpenCodeAPIClient()
  }
}
