import ComposableArchitecture
import DependencyClients
import DependencyClientsLive
import Features
import Models
import SwiftUI
import Views

@main
public struct OpenCoderApp: App {
  public init() {}

  public var body: some Scene {
    let configuration = Self.resolveConfiguration()

    return WindowGroup {
      AppView(
        store: Store(
          initialState: AppFeature.State(),
          reducer: { AppFeature() },
          withDependencies: {
            $0.openCodeConfiguration = configuration
            $0.openCodeAPI = LiveOpenCodeAPIClient(configuration: configuration)
          }
        )
      )
    }
  }
}

private extension OpenCoderApp {
  static func resolveConfiguration() -> OpenCodeConfiguration {
    guard let environment = Bundle.main.object(forInfoDictionaryKey: "OPENCODE_ENV") as? String else {
      return .development
    }

    switch environment.lowercased() {
    case "production":
      return .production
    default:
      return .development
    }
  }
}
