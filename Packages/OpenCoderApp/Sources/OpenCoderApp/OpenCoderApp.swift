import ComposableArchitecture
import OpenCoderCore
import OpenCoderUI
import SwiftUI

@main
public struct OpenCoderApp: App {
  public init() {
    print("OpenCoderApp init: Setting up dependencies")
  }

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
                print("Creating LiveOpenCodeAPIClient for config: \(config)")
                return LiveOpenCodeAPIClient(configuration: config)
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
