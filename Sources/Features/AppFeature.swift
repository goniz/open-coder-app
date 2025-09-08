import ComposableArchitecture
import Models

@Reducer
package struct AppFeature {
  @ObservableState
  package struct State: Equatable {
    package var home = HomeFeature.State()
    package var onboarding = OnboardingFeature.State()
    package var showOnboarding = true

    package init() {}
  }

  package enum Action: Equatable {
    case task
    case home(HomeFeature.Action)
    case onboarding(OnboardingFeature.Action)
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
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      return .none

    case .home:
      return .none
      
    case .onboarding(.skipOnboarding), .onboarding(.completeOnboarding):
      state.showOnboarding = false
      return .none
      
    case .onboarding:
      return .none
      
    case .dismissOnboarding:
      state.showOnboarding = false
      return .none
    }
  }
}
