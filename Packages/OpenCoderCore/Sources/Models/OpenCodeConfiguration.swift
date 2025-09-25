import Foundation

public struct OpenCodeConfiguration: Equatable, Sendable {
  public let serverURL: URL
  public let timeout: TimeInterval
  public let retryCount: Int

  public init(
    serverURL: URL = URL(string: "http://localhost:8080")!,
    timeout: TimeInterval = 30,
    retryCount: Int = 3
  ) {
    self.serverURL = serverURL
    self.timeout = timeout
    self.retryCount = retryCount
  }

  public static let development = OpenCodeConfiguration(
    serverURL: URL(string: "http://localhost:8080")!
  )

  public static let production = OpenCodeConfiguration(
    serverURL: URL(string: "https://api.opencode.app")!,
    timeout: 30,
    retryCount: 3
  )
}
