import ComposableArchitecture
import OpenCoderCore
import OpenCoderUI
import SwiftUI

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
            $0.openCodeAPIFactory = OpenCodeAPIClientFactory { config in
              LiveOpenCodeAPIClient(configuration: config)
            }
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
