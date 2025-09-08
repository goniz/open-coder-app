import ComposableArchitecture
import Features
import XCTest

@MainActor
final class HomeFeatureTests: XCTestCase {
  func testTabSelection() async throws {
    let store = TestStore(
      initialState: HomeFeature.State(),
      reducer: { HomeFeature() }
    )

    await store.send(.tabSelected(.projects)) {
      $0.selectedTab = .projects
    }
  }
}
