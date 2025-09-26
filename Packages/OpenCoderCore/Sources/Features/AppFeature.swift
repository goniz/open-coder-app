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

    public init() {}
  }

  public enum Action: Equatable, Sendable {
    case task
    case home(HomeFeature.Action)
    case onboarding(OnboardingFeature.Action)
    case liveActivity(LiveActivityFeature.Action)
    case dismissOnboarding
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
      let config = OpenCodeConfiguration.development
      let client = openCodeAPIFactory.make(config)
      state.showOnboarding = !hasSavedServers()

      // Log async to avoid actor isolation issues
      return .run { _ in
        await MainActor.run {
          AppLogger.shared.log(
            "AppFeature.task: Created client type: \(type(of: client))",
            level: .info,
            category: .general
          )
        }
      }

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
