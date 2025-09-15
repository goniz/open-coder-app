import ComposableArchitecture
import DependencyClients
import Foundation
import Models

@Reducer
package struct WorkspaceInteractionFeature {
  package enum Tab: String, CaseIterable, Equatable {
    case activity = "Activity"
    case chat = "Chat"
    case terminal = "Terminal"
    case files = "Files"
  }

  @ObservableState
  package struct State: Equatable {
    package var workspace: Workspace
    package var onlineState: WorkspaceOnlineState
    package var selectedTab: Tab = .activity
    package var chat = ChatFeature.State()
    package var serverConnection: ConnectionState = .disconnected

    package init(workspace: Workspace, onlineState: WorkspaceOnlineState) {
      self.workspace = workspace
      self.onlineState = onlineState
    }
  }

  package enum Action: Equatable {
    case task
    case serverConnectionRefreshed(ConnectionState)
    case tabSelected(Tab)
    case chat(ChatFeature.Action)
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    Scope(state: \.chat, action: \.chat) {
      ChatFeature()
    }
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      // Query the shared pool for current server connection status
      let workspace = state.workspace
      return .run { send in
        if let config = WorkspacesStorage.loadSSHConfigForWorkspace(workspace) {
          let isConnected = await SSHConnectionPool.shared.isConnected(serverConfigID: config.id)
          await send(.serverConnectionRefreshed(isConnected ? .connected : .disconnected))
        } else {
          await send(.serverConnectionRefreshed(.disconnected))
        }
      }

    case let .serverConnectionRefreshed(status):
      state.serverConnection = status
      return .none

    case let .tabSelected(tab):
      state.selectedTab = tab
      return .none

    case .chat:
      return .none
    }
  }
}
