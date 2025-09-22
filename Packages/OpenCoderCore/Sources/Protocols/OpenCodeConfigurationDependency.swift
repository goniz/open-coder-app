import Dependencies
import Models

package enum OpenCodeConfigurationKey: DependencyKey {
  package static let liveValue: OpenCodeConfiguration = .development
  package static let testValue: OpenCodeConfiguration = .development
}

extension DependencyValues {
  package var openCodeConfiguration: OpenCodeConfiguration {
    get { self[OpenCodeConfigurationKey.self] }
    set { self[OpenCodeConfigurationKey.self] = newValue }
  }
}
