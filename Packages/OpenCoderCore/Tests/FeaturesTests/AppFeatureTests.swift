import ComposableArchitecture
import Features
import Models
import Protocols
import XCTest

@MainActor
final class AppFeatureTests: XCTestCase {
  func testTask() async throws {
    let store = TestStore(
      initialState: AppFeature.State(),
      reducer: {
        AppFeature()
      },
      withDependencies: {
        $0.openCodeAPIFactory = TestMockFactory()
      }
    )
    
    store.exhaustivity = .off

    await store.send(.task)
  }
}

private struct TestMockFactory: OpenCodeAPIClientFactoryProtocol {
  let make: @Sendable (OpenCodeConfiguration) -> OpenCodeAPIClientProtocol = { _ in
    return MockOpenCodeAPIClient()
  }
}
