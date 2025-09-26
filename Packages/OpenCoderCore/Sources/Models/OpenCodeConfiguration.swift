import Foundation

public struct OpenCodeConfiguration: Equatable, Sendable {
  public let serverURL: URL
  public let timeout: TimeInterval
  public let retryCount: Int

  public init(
    serverURL: URL,
    timeout: TimeInterval = 30,
    retryCount: Int = 3
  ) {
    self.serverURL = serverURL
    self.timeout = timeout
    self.retryCount = retryCount
  }

  public static let development = OpenCodeConfiguration(
    serverURL: URL(string: "http://127.0.0.1:8080")!
  )

  public static let production = OpenCodeConfiguration(
    serverURL: URL(string: "https://api.opencode.app")!,
    timeout: 30,
    retryCount: 3
  )
}
