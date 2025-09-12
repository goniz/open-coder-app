import ComposableArchitecture
import Models

@Reducer
package struct SettingsFeature {
  @ObservableState
  package struct State: Equatable {
    package var theme: Theme = .system
    package var notificationsEnabled = true
    package var autoSaveEnabled = true
    package var showingLogs = false

    package init() {}
  }

  package enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case task
    case resetToDefaults
    case toggleLogs
    case clearLogs
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
      return .run { _ in
      }

    case .resetToDefaults:
      state = State()
      return .none

    case .toggleLogs:
      state.showingLogs.toggle()
      return .none

    case .clearLogs:
      return .run { _ in
        await AppLogger.shared.clearLogs()
      }
    }
  }
}

package enum Theme: String, Equatable, CaseIterable {
  case light
  case dark
  case system
}
