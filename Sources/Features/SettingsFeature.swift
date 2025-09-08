import ComposableArchitecture

@Reducer
package struct SettingsFeature {
  @ObservableState
  package struct State: Equatable {
    package var theme: Theme = .system
    package var notificationsEnabled = true
    package var autoSaveEnabled = true

    package init() {}
  }

  package enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case task
    case resetToDefaults
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .binding:
      return .none

    case .task:
      return .run { send in
        // TODO: Load settings from storage
      }

    case .resetToDefaults:
      state = State()
      return .none
    }
  }
}

package enum Theme: String, Equatable, CaseIterable {
  case light
  case dark
  case system
}