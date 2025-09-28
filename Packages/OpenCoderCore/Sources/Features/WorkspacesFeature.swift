import ComposableArchitecture
import Protocols
import Implementations
import Dependencies
import Foundation
import Models

@Reducer
public struct WorkspacesFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var workspaces: [WorkspaceState] = []
    public var isLoading = false
    public var isAddingWorkspace = false
    public var selectedWorkspace: WorkspaceState.ID?
    public var showingWorkspaceInteraction = false
    public var interactionInitialTab: WorkspaceInteractionFeature.Tab = .activity
    public var workspaceInteraction: WorkspaceInteractionFeature.State?
    @ObservationStateIgnored public var portForwardTokens: [WorkspaceState.ID: PortForwardToken] = [:]

    public init() {}
  }

  public struct WorkspaceState: Equatable, Identifiable, Sendable {
    public var id: Workspace.ID { workspace.id }
    public var workspace: Workspace
    public var onlineState: WorkspaceOnlineState = .idle
    public var lastConnectedAt: Date?
    public var openCodeSession: OpenCodeSession?
    public var openCodeSessions: [OpenCodeSession] = []
    public var remotePort: Int?
    public var forwardedPort: Int?
    public var sessions: [SessionMeta] = []
    public var isRefreshing = false

    public init(workspace: Workspace) {
      self.workspace = workspace
    }
  }

  public enum Action: Equatable, Sendable {
    case task
    case workspacesLoaded([WorkspaceState])
    case addWorkspace
    case addWorkspaceCompleted(Workspace)
    case openWorkspace(WorkspaceState.ID)
    case workspaceOpened(WorkspaceState.ID, Result<WorkspaceService.SpawnResult, SSHError>)
    case refreshWorkspace(WorkspaceState.ID)
    case workspaceRefreshed(WorkspaceState.ID, [SessionMeta], [OpenCodeSession])
    case removeWorkspace(WorkspaceState.ID)
    case dismissAddWorkspace
    case showLiveOutput(WorkspaceState.ID)
    case cleanAndRetry(WorkspaceState.ID)
    case spawnPhaseUpdated(WorkspaceState.ID, SpawnPhase)
    case hideWorkspaceInteraction
    case workspacePortForwardEstablished(WorkspaceState.ID, PortForwardToken)
    case workspaceInteraction(WorkspaceInteractionFeature.Action)
  }

  public init() {}

  @Dependency(\.openCodeConfiguration) var openCodeConfiguration
  @Dependency(\.portForwarding) var portForwarding
  @Dependency(\.openCodeAPIFactory) var openCodeAPIFactory

  public var body: some ReducerOf<Self> {
    Reduce(core)
      .ifLet(
        \.workspaceInteraction,
        action: \.workspaceInteraction
      ) {
        WorkspaceInteractionFeature()
      }
  }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  public func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      return handleTask(state: &state)

    case let .workspacesLoaded(workspaces):
      return handleWorkspacesLoaded(state: &state, workspaces: workspaces)

    case .addWorkspace:
      return handleAddWorkspace(state: &state)

    case let .addWorkspaceCompleted(workspace):
      return handleAddWorkspaceCompleted(state: &state, workspace: workspace)

    case let .openWorkspace(id):
      let workspaceCount = state.workspaces.count
      Task {
        await AppLogger.shared.log(
          "WorkspacesFeature received openWorkspace action for id: \(id), state has \(workspaceCount) workspaces",
          level: .debug,
          category: .workspace
        )
      }
      let result = handleOpenWorkspace(state: &state, id: id)
      Task {
        await AppLogger.shared.log(
          "handleOpenWorkspace completed successfully for id: \(id)",
          level: .debug,
          category: .workspace
        )
      }
      return result

    case let .workspaceOpened(id, result):
      return handleWorkspaceOpened(state: &state, id: id, result: result)

    case let .refreshWorkspace(id):
      return handleRefreshWorkspace(state: &state, id: id)

    case let .workspaceRefreshed(id, sessions, openCodeSessions):
      return handleWorkspaceRefreshed(
        state: &state,
        id: id,
        sessions: sessions,
        openCodeSessions: openCodeSessions
      )

    case let .removeWorkspace(id):
      return handleRemoveWorkspace(state: &state, id: id)

    case .dismissAddWorkspace:
      return handleDismissAddWorkspace(state: &state)

    case let .showLiveOutput(id):
      return handleShowLiveOutput(state: &state, id: id)

    case let .cleanAndRetry(id):
      return handleCleanAndRetry(state: &state, id: id)

    case let .spawnPhaseUpdated(id, phase):
      return handleSpawnPhaseUpdated(state: &state, id: id, phase: phase)

    case let .workspacePortForwardEstablished(id, token):
      return handlePortForwardEstablished(state: &state, id: id, token: token)

    case .hideWorkspaceInteraction:
      return handleHideWorkspaceInteraction(state: &state)

    case .workspaceInteraction:
      return .none
    }
  }

}
