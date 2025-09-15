import ComposableArchitecture
import DependencyClients
import Models

@Reducer
package struct HomeFeature {
  @ObservableState
  package struct State: Equatable {
    package var selectedTab: Tab = .servers
    package var workspaces = WorkspacesFeature.State()
    package var servers = ServersFeature.State()
    package var settings = SettingsFeature.State()

    package init() {}
  }

  package enum Action: Equatable {
    case tabSelected(Tab)
    case workspaces(WorkspacesFeature.Action)
    case servers(ServersFeature.Action)
    case settings(SettingsFeature.Action)
  }

  package enum Tab: Equatable {
    case workspaces
    case servers
    case settings
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    Scope(state: \.workspaces, action: \.workspaces) {
      WorkspacesFeature()
    }
    Scope(state: \.servers, action: \.servers) {
      ServersFeature()
    }
    Scope(state: \.settings, action: \.settings) {
      SettingsFeature()
    }
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .tabSelected(tab):
      state.selectedTab = tab
      return .none

    case .workspaces(.task), .servers(.task), .settings(.task):
      return .none

    case .workspaces, .servers, .settings:
      return .none
    }
  }
}
