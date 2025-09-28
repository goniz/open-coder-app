import Dependencies
import Models

public enum OpenCodeConfigurationKey: DependencyKey, Sendable {
  public static let liveValue: OpenCodeConfiguration = .development
  public static let testValue: OpenCodeConfiguration = .development
}

extension DependencyValues {
  public var openCodeConfiguration: OpenCodeConfiguration {
    get { self[OpenCodeConfigurationKey.self] }
    set { self[OpenCodeConfigurationKey.self] = newValue }
  }
}
