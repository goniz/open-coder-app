import ComposableArchitecture
import Protocols
import Implementations
import Foundation
import Models

@Reducer
public struct WorkspaceInteractionFeature: Sendable {
  public enum Tab: String, CaseIterable, Equatable, Sendable {
    case activity = "Activity"
    case chat = "Chat"
    case terminal = "Terminal"
    case files = "Files"
    case liveOutput = "Live Output"
  }

  @ObservableState
  public struct State: Equatable, Sendable {
    public var workspace: Workspace
    public var onlineState: WorkspaceOnlineState
    public var selectedTab: Tab
    public var serverConnection: ConnectionState = .disconnected
    public var forwardedPort: Int?
    public var openCodeServerURL: URL?
    public var openCodeSessionID: String?
    public var activityEvents: [ActivityEvent] = []
    public var previousOnlineState: WorkspaceOnlineState?

    public init(
      workspace: Workspace,
      onlineState: WorkspaceOnlineState,
      selectedTab: Tab = .activity,
      forwardedPort: Int? = nil,
      openCodeServerURL: URL? = nil,
      openCodeSessionID: String? = nil,
      activityEvents: [ActivityEvent] = [],
      previousOnlineState: WorkspaceOnlineState? = nil
    ) {
      self.workspace = workspace
      self.onlineState = onlineState
      self.selectedTab = selectedTab
      self.forwardedPort = forwardedPort
      if let forwardedPort,
         openCodeServerURL == nil {
        self.openCodeServerURL = URL(string: "http://127.0.0.1:\(forwardedPort)")
      } else {
        self.openCodeServerURL = openCodeServerURL
      }
      self.openCodeSessionID = openCodeSessionID
      self.activityEvents = activityEvents
      self.previousOnlineState = previousOnlineState
    }
  }

  public enum Action: Equatable, Sendable {
    case task
    case serverConnectionRefreshed(ConnectionState)
    case tabSelected(Tab)
    case openCodeSessionUpdated(OpenCodeSession?)
    case forwardedPortUpdated(Int?)
    case addActivityEvent(ActivityEvent)
    case clearActivityEvents
    case onlineStateChanged(WorkspaceOnlineState)
    case retryConnection
    case dismiss
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce(core)
  }

  public func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      return handleTaskAction(state: &state)

    case let .serverConnectionRefreshed(status):
      return handleServerConnectionRefreshed(state: &state, status: status)

    case let .tabSelected(tab):
      return handleTabSelected(state: &state, tab: tab)

    case let .openCodeSessionUpdated(session):
      return handleOpenCodeSessionUpdated(state: &state, session: session)

    case let .forwardedPortUpdated(port):
      return handleForwardedPortUpdated(state: &state, port: port)

    case let .addActivityEvent(event):
      return handleAddActivityEvent(state: &state, event: event)

    case .clearActivityEvents:
      return handleClearActivityEvents(state: &state)

    case let .onlineStateChanged(newState):
      return handleOnlineStateChanged(state: &state, newState: newState)

    case .retryConnection:
      return handleRetryConnection(state: &state)

    case .dismiss:
      return .none // This action will be handled by the parent feature
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

  private func handleOpenCodeSessionUpdated(state: inout State, session: OpenCodeSession?) -> Effect<Action> {
    state.openCodeSessionID = session?.id
    return .none
  }

  private func handleForwardedPortUpdated(state: inout State, port: Int?) -> Effect<Action> {
    state.forwardedPort = port
    state.openCodeServerURL = port.flatMap { URL(string: "http://127.0.0.1:\($0)") }
    if let port {
      // Create activity event for port forwarding
      let event = ActivityEvent(
        type: .portForwarding,
        message: "SSH port forwarding established on port \(port)"
      )
      return .send(.addActivityEvent(event))
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

  private func handleRetryConnection(state: inout State) -> Effect<Action> {
    // Reset the online state and trigger a retry
    state.onlineState = .idle

    // Add activity event for retry attempt
    let event = ActivityEvent(
      type: .sshConnection,
      message: "Retrying workspace connection..."
    )

    return .merge(
      .send(.addActivityEvent(event)),
      .send(.task)
    )
  }
}

// MARK: - Activity Event Creation

private extension WorkspaceInteractionFeature {
  func createConnectionEvent(
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

  func createOnlineStateEvent(
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

  func createSpawningEvent(
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

  func createErrorEvent(for state: WorkspaceOnlineState) -> ActivityEvent? {
    if case let .error(message) = state {
      return ActivityEvent(
        type: .workspaceError,
        message: "Workspace error: \(message)",
        isError: true
      )
    }
    return nil
  }
}
