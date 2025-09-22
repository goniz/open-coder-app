import Dependencies
import Models

package struct OpenCodeAPIClientFactory: Sendable {
  package var make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol

  package init(make: @escaping @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol) {
    self.make = make
  }
}

package enum OpenCodeAPIClientFactoryKey: DependencyKey {
  package static let liveValue = OpenCodeAPIClientFactory { _ in
    MockOpenCodeAPIClient()
  }
  package static let testValue = OpenCodeAPIClientFactory { _ in
    MockOpenCodeAPIClient()
  }
}

extension DependencyValues {
  package var openCodeAPIFactory: OpenCodeAPIClientFactory {
    get { self[OpenCodeAPIClientFactoryKey.self] }
    set { self[OpenCodeAPIClientFactoryKey.self] = newValue }
  }
}
