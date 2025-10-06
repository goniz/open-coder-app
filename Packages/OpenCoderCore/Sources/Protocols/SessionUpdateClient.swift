import Foundation
import Models
import Dependencies

public struct SessionUpdateClient: Sendable {
  public var sessionUpdated: @Sendable (OpenCodeSession) -> Void

  public init(sessionUpdated: @escaping @Sendable (OpenCodeSession) -> Void) {
    self.sessionUpdated = sessionUpdated
  }
}

extension SessionUpdateClient: DependencyKey {
  public static var liveValue: SessionUpdateClient {
    SessionUpdateClient { _ in
      // Default no-op implementation
    }
  }

  public static var testValue: SessionUpdateClient {
    SessionUpdateClient { _ in
      // Test no-op implementation
    }
  }
}

extension DependencyValues {
  public var sessionUpdateClient: SessionUpdateClient {
    get { self[SessionUpdateClient.self] }
    set { self[SessionUpdateClient.self] = newValue }
  }
}
