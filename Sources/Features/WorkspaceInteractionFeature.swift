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
    case liveOutput = "Live Output"
  }

  @ObservableState
  package struct State: Equatable {
    package var workspace: Workspace
    package var onlineState: WorkspaceOnlineState
    package var selectedTab: Tab
    package var chat: ChatFeature.State
    package var serverConnection: ConnectionState = .disconnected
    package var forwardedPort: Int?

    package init(
      workspace: Workspace,
      onlineState: WorkspaceOnlineState,
      selectedTab: Tab = .activity,
      sessionID: String? = nil,
      forwardedPort: Int? = nil
    ) {
      self.workspace = workspace
      self.onlineState = onlineState
      self.selectedTab = selectedTab
      if let forwardedPort {
        let serverURL = URL(string: "http://127.0.0.1:\(forwardedPort)")
        self.chat = ChatFeature.State(sessionID: sessionID, serverURL: serverURL)
      } else {
        self.chat = ChatFeature.State(sessionID: sessionID)
      }
      self.forwardedPort = forwardedPort
    }
  }

  package enum Action: Equatable {
    case task
    case serverConnectionRefreshed(ConnectionState)
    case tabSelected(Tab)
    case chat(ChatFeature.Action)
    case openCodeSessionUpdated(OpenCodeSession?)
    case forwardedPortUpdated(Int?)
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

    case let .openCodeSessionUpdated(session):
      return .send(.chat(.updateSession(session?.id)))

    case let .forwardedPortUpdated(port):
      state.forwardedPort = port
      if let port {
        state.chat.serverURL = URL(string: "http://127.0.0.1:\(port)")
      } else {
        state.chat.serverURL = nil
      }
      return .none

    case .chat:
      return .none
    }
  }
}
