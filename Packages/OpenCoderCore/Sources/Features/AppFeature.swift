import ComposableArchitecture
import Foundation
import Models

@Reducer
package struct AppFeature {
  @ObservableState
  package struct State: Equatable {
    package var home = HomeFeature.State()
    package var onboarding = OnboardingFeature.State()
    package var liveActivity = LiveActivityFeature.State()
    package var showOnboarding = true

    package init() {}
  }

  package enum Action: Equatable {
    case task
    case home(HomeFeature.Action)
    case onboarding(OnboardingFeature.Action)
    case liveActivity(LiveActivityFeature.Action)
    case dismissOnboarding
  }

  package init() {}

  package var body: some ReducerOf<Self> {
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

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
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
