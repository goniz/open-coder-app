import ComposableArchitecture
import OpenCoderCore
import OpenCoderUI
import SwiftUI

@main
public struct OpenCoderApp: App {
  public init() {
    AppLogger.shared.log("OpenCoderApp init: Setting up dependencies", level: .info, category: .general)
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
              AppLogger.shared.log("OpenCoderApp: Setting live factory", level: .info, category: .general)
              $0.openCodeAPIFactory = OpenCodeAPIClientFactory.live
              $0.portForwarding = LivePortForwardingClient()
              AppLogger.shared.log("OpenCoderApp: Factory configured", level: .info, category: .general)
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
