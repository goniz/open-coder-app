import Foundation

package struct OpenCodeConfiguration: Equatable, Sendable {
  package let serverURL: URL
  package let timeout: TimeInterval
  package let retryCount: Int

  package init(
    serverURL: URL = URL(string: "http://localhost:8080")!,
    timeout: TimeInterval = 30,
    retryCount: Int = 3
  ) {
    self.serverURL = serverURL
    self.timeout = timeout
    self.retryCount = retryCount
  }

  package static let development = OpenCodeConfiguration(
    serverURL: URL(string: "http://localhost:8080")!
  )

  package static let production = OpenCodeConfiguration(
    serverURL: URL(string: "https://api.opencode.app")!,
    timeout: 30,
    retryCount: 3
  )
}
