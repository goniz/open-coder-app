import Dependencies
import Models

public protocol OpenCodeAPIClientFactoryProtocol: Sendable {
  var make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol { get }
}

public enum OpenCodeAPIClientFactoryDependencyKey: DependencyKey, Sendable {
  public static let liveValue: OpenCodeAPIClientFactoryProtocol = MockFactory() // Default fallback
  public static let testValue: OpenCodeAPIClientFactoryProtocol = MockFactory()
}

public extension DependencyValues {
  var openCodeAPIFactory: OpenCodeAPIClientFactoryProtocol {
    get { self[OpenCodeAPIClientFactoryDependencyKey.self] }
    set { self[OpenCodeAPIClientFactoryDependencyKey.self] = newValue }
  }
}

private struct MockFactory: OpenCodeAPIClientFactoryProtocol {
  let make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol = { _ in
    Task { @MainActor in
      AppLogger.shared.log("Creating MockOpenCodeAPIClient (fallback)", level: .warning, category: .api)
    }
    return MockOpenCodeAPIClient()
  }
}
