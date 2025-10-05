import ComposableArchitecture
import Protocols
import Models

@Reducer
public struct HomeFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var selectedTab: Tab = .servers
    public var workspaces = WorkspacesFeature.State()
    public var servers = ServersFeature.State()
    public var settings = SettingsFeature.State()

    public init() {}
  }

  public enum Action: Equatable, Sendable {
    case tabSelected(Tab)
    case workspaces(WorkspacesFeature.Action)
    case servers(ServersFeature.Action)
    case settings(SettingsFeature.Action)
  }

  public enum Tab: Equatable, Sendable {
    case workspaces
    case servers
    case settings
  }

  public init() {}

  public var body: some ReducerOf<Self> {
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

  public func core(state: inout State, action: Action) -> Effect<Action> {
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

    case .workspaces, .servers:
      return .none

    case .settings:
      // Sync settings to workspaces
      state.workspaces.settings = state.settings
      return .none
    }
  }
}
