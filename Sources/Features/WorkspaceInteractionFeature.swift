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
    package var activityEvents: [ActivityEvent] = []
    package var previousOnlineState: WorkspaceOnlineState?

    package init(
      workspace: Workspace,
      onlineState: WorkspaceOnlineState,
      selectedTab: Tab = .activity,
      sessionID: String? = nil,
      forwardedPort: Int? = nil,
      activityEvents: [ActivityEvent] = [],
      previousOnlineState: WorkspaceOnlineState? = nil
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
      self.activityEvents = activityEvents
      self.previousOnlineState = previousOnlineState
    }
  }

  package enum Action: Equatable {
    case task
    case serverConnectionRefreshed(ConnectionState)
    case tabSelected(Tab)
    case chat(ChatFeature.Action)
    case openCodeSessionUpdated(OpenCodeSession?)
    case forwardedPortUpdated(Int?)
    case addActivityEvent(ActivityEvent)
    case clearActivityEvents
    case onlineStateChanged(WorkspaceOnlineState)
  }

  package init() {}

  private func createConnectionEvent(
    from previousStatus: ConnectionState,
    to newStatus: ConnectionState
  ) -> ActivityEvent? {
    switch (previousStatus, newStatus) {
    case (.disconnected, .connecting):
      return ActivityEvent(
        type: .sshConnection,
        message: "Connecting to SSH server..."
      )
    case (.connecting, .connected):
      return ActivityEvent(
        type: .sshConnection,
        message: "SSH connection established successfully"
      )
    case (.connected, .disconnected):
      return ActivityEvent(
        type: .sshConnection,
        message: "SSH connection lost",
        isError: true
      )
    case (.connecting, .error), (.connected, .error), (.disconnected, .error):
      if case let .error(message) = newStatus {
        return ActivityEvent(
          type: .sshConnection,
          message: "SSH connection error: \(message)",
          isError: true
        )
      }
      return nil
    default:
      return nil
    }
  }

  private func createOnlineStateEvent(
    from previousState: WorkspaceOnlineState,
    to newState: WorkspaceOnlineState
  ) -> ActivityEvent? {
    // Handle spawning phase transitions
    if let event = createSpawningEvent(from: previousState, to: newState) {
      return event
    }

    // Handle online to idle transition
    if case (.online, .idle) = (previousState, newState) {
      return ActivityEvent(
        type: .workspaceOnline,
        message: "Workspace went idle",
        isError: true
      )
    }

    // Handle error states
    if case .error = newState {
      return createErrorEvent(for: newState)
    }

    return nil
  }

  private func createSpawningEvent(
    from previousState: WorkspaceOnlineState,
    to newState: WorkspaceOnlineState
  ) -> ActivityEvent? {
    switch (previousState, newState) {
    case (.idle, .spawning(.sshConnection)):
      return ActivityEvent(
        type: .sshConnection,
        message: "Starting workspace initialization..."
      )
    case (.spawning(.sshConnection), .spawning(.openCodeSpawn)):
      return ActivityEvent(
        type: .openCodeSpawn,
        message: "OpenCode workspace services are starting..."
      )
    case (.spawning(.openCodeSpawn), .spawning(.portForwarding)):
      return ActivityEvent(
        type: .portForwarding,
        message: "Setting up SSH port forwarding..."
      )
    case (.spawning(.portForwarding), .spawning(.apiHandshake)):
      return ActivityEvent(
        type: .apiConnection,
        message: "Connecting to OpenCode API..."
      )
    case (.spawning(.apiHandshake), .online):
      if case let .online(port) = newState {
        return ActivityEvent(
          type: .workspaceOnline,
          message: "Workspace is now online and ready on port \(port)"
        )
      }
      return nil
    default:
      return nil
    }
  }

  private func createErrorEvent(for state: WorkspaceOnlineState) -> ActivityEvent? {
    if case let .error(message) = state {
      return ActivityEvent(
        type: .workspaceError,
        message: "Workspace error: \(message)",
        isError: true
      )
    }
    return nil
  }

  package var body: some ReducerOf<Self> {
    Scope(state: \.chat, action: \.chat) {
      ChatFeature()
    }
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      return handleTaskAction(state: &state)

    case let .serverConnectionRefreshed(status):
      return handleServerConnectionRefreshed(state: &state, status: status)

    case let .tabSelected(tab):
      return handleTabSelected(state: &state, tab: tab)

    case let .openCodeSessionUpdated(session):
      return handleOpenCodeSessionUpdated(session: session)

    case let .forwardedPortUpdated(port):
      return handleForwardedPortUpdated(state: &state, port: port)

    case let .addActivityEvent(event):
      return handleAddActivityEvent(state: &state, event: event)

    case .clearActivityEvents:
      return handleClearActivityEvents(state: &state)

    case let .onlineStateChanged(newState):
      return handleOnlineStateChanged(state: &state, newState: newState)

    case .chat:
      return .none
    }
  }

  private func handleTaskAction(state: inout State) -> Effect<Action> {
    let workspace = state.workspace
    return .run { send in
      if let config = WorkspacesStorage.loadSSHConfigForWorkspace(workspace) {
        let isConnected = await SSHConnectionPool.shared.isConnected(serverConfigID: config.id)
        await send(.serverConnectionRefreshed(isConnected ? .connected : .disconnected))
      } else {
        await send(.serverConnectionRefreshed(.disconnected))
      }
    }
  }

  private func handleServerConnectionRefreshed(state: inout State, status: ConnectionState) -> Effect<Action> {
    let previousStatus = state.serverConnection
    state.serverConnection = status

    // Create activity event for connection state changes
    if previousStatus != status {
      if let event = createConnectionEvent(from: previousStatus, to: status) {
        return .send(.addActivityEvent(event))
      }
    }
    return .none
  }

  private func handleTabSelected(state: inout State, tab: Tab) -> Effect<Action> {
    state.selectedTab = tab
    return .none
  }

  private func handleOpenCodeSessionUpdated(session: OpenCodeSession?) -> Effect<Action> {
    return .send(.chat(.updateSession(session?.id)))
  }

  private func handleForwardedPortUpdated(state: inout State, port: Int?) -> Effect<Action> {
    state.forwardedPort = port
    if let port {
      state.chat.serverURL = URL(string: "http://127.0.0.1:\(port)")
      // Create activity event for port forwarding
      let event = ActivityEvent(
        type: .portForwarding,
        message: "SSH port forwarding established on port \(port)"
      )
      return .send(.addActivityEvent(event))
    } else {
      state.chat.serverURL = nil
    }
    return .none
  }

  private func handleAddActivityEvent(state: inout State, event: ActivityEvent) -> Effect<Action> {
    state.activityEvents.append(event)
    // Keep only the last 100 events to prevent memory issues
    if state.activityEvents.count > 100 {
      state.activityEvents.removeFirst(state.activityEvents.count - 100)
    }
    return .none
  }

  private func handleClearActivityEvents(state: inout State) -> Effect<Action> {
    state.activityEvents.removeAll()
    return .none
  }

  private func handleOnlineStateChanged(state: inout State, newState: WorkspaceOnlineState) -> Effect<Action> {
    let previousState = state.previousOnlineState ?? state.onlineState
    state.previousOnlineState = state.onlineState
    state.onlineState = newState

    // Create activity event for online state changes
    if previousState != newState {
      if let event = createOnlineStateEvent(from: previousState, to: newState) {
        return .send(.addActivityEvent(event))
      }
    }
    return .none
  }
}
