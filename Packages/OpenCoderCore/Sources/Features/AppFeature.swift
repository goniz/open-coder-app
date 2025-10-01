import ComposableArchitecture
import Foundation
import Models

@Reducer
public struct AppFeature: Sendable {
  @Dependency(\.openCodeAPIFactory) var openCodeAPIFactory

  @ObservableState
  public struct State: Equatable, Sendable {
    public var home = HomeFeature.State()
    public var onboarding = OnboardingFeature.State()
    public var liveActivity = LiveActivityFeature.State()
    public var showOnboarding = true
    public var globalError: String?

    public init() {}
  }

  public enum Action: Equatable, Sendable {
    case task
    case home(HomeFeature.Action)
    case onboarding(OnboardingFeature.Action)
    case liveActivity(LiveActivityFeature.Action)
    case dismissOnboarding
    case globalErrorOccurred(String)
    case dismissGlobalError
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Scope(state: \.home, action: \.home) {
      HomeFeature()
    }
    Scope(state: \.onboarding, action: \.onboarding) {
      OnboardingFeature()
    }
    Scope(state: \.liveActivity, action: \.liveActivity) {
      LiveActivityFeature()
    }
    Reduce(core)
  }

  public func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      // Test the factory and client creation
      Task {
        await AppLogger.shared.log(
          "AppFeature.task: Factory type: \(type(of: openCodeAPIFactory))",
          level: .debug,
          category: .app
        )
      }
      let config = OpenCodeConfiguration.development
      Task {
        await AppLogger.shared.log(
          "AppFeature.task: About to create client with factory",
          level: .debug,
          category: .app
        )
      }
      let client = openCodeAPIFactory.make(config)
      Task {
        await AppLogger.shared.log(
          "AppFeature.task: Created client type: \(type(of: client))",
          level: .debug,
          category: .app
        )
      }
      state.showOnboarding = !hasSavedServers()

      return .none

    case .home:
      return .none

    case .onboarding(.skipOnboarding), .onboarding(.completeOnboarding):
      state.showOnboarding = false
      return .send(.home(.servers(.task)))

    case .onboarding:
      return .none

    case .liveActivity:
      return .none

    case .dismissOnboarding:
      state.showOnboarding = false
      return .none
    
    case let .globalErrorOccurred(error):
      state.globalError = error
      return .none
    
    case .dismissGlobalError:
      state.globalError = nil
      return .none
    }
  }

  private func hasSavedServers() -> Bool {
    guard let data = UserDefaults.standard.data(forKey: "savedServers") else { return false }
    do {
      let configurations = try JSONDecoder().decode([SSHServerConfiguration].self, from: data)
      return !configurations.isEmpty
    } catch {
      return false
    }
  }
}
