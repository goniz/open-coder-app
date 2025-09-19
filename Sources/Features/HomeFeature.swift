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

    // Reflect a successful workspace connection in Servers tab connection state
    case let .workspaces(.workspaceOpened(workspaceID, result)):
      switch result {
      case .success(let spawnResult) where spawnResult.online:
        if let workspaceState = state.workspaces.workspaces.first(where: { $0.id == workspaceID }) {
          // Prefer explicit serverID mapping, otherwise match by host+user
          if let serverConfigID = workspaceState.workspace.serverID,
            let server = state.servers.servers.first(where: {
              $0.configuration.id == serverConfigID
            }) {
            return .send(.servers(.connectionSuccess(server.id)))
          } else if let server = state.servers.servers.first(where: {
            $0.configuration.host == workspaceState.workspace.host
              && $0.configuration.username == workspaceState.workspace.user
          }) {
            return .send(.servers(.connectionSuccess(server.id)))
          }
        }
        return .none
      default:
        return .none
      }

    case .workspaces, .servers, .settings:
      return .none
    }
  }
}
