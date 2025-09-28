import Dependencies
import Models
@testable import Protocols
import XCTest

final class OpenCodeConfigurationDependencyTests: XCTestCase {
  func testDefaultConfigurationIsDevelopment() {
    let configuration = DependencyValues().openCodeConfiguration
    XCTAssertEqual(configuration, .development)
  }

  func testOverrideConfigurationResolvesInjectedValue() {
    let customConfiguration = OpenCodeConfiguration(
      serverURL: URL(string: "https://example.com")!,
      timeout: 45,
      retryCount: 2
    )

    let resolvedConfiguration = withDependencies {
      $0.openCodeConfiguration = customConfiguration
    } operation: {
      @Dependency(\.openCodeConfiguration) var openCodeConfiguration
      return openCodeConfiguration
    }

    XCTAssertEqual(resolvedConfiguration, customConfiguration)
  }
}
