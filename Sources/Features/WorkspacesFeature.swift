import ComposableArchitecture
import DependencyClients
import Dependencies
import Foundation
import Models

@Reducer
package struct WorkspacesFeature {
  @ObservableState
  package struct State: Equatable {
    package var workspaces: [WorkspaceState] = []
    package var isLoading = false
    package var isAddingWorkspace = false
    package var selectedWorkspace: WorkspaceState.ID?
    package var showingWorkspaceInteraction = false
    package var interactionInitialTab: WorkspaceInteractionFeature.Tab = .activity
    package var workspaceInteraction: WorkspaceInteractionFeature.State?
    @ObservationStateIgnored package var portForwardTokens: [WorkspaceState.ID: PortForwardToken] = [:]

    package init() {}
  }

  package struct WorkspaceState: Equatable, Identifiable {
    package let id = UUID()
    package var workspace: Workspace
    package var onlineState: WorkspaceOnlineState = .idle
    package var lastConnectedAt: Date?
    package var openCodeSession: OpenCodeSession?
    package var openCodeSessions: [OpenCodeSession] = []
    package var remotePort: Int?
    package var forwardedPort: Int?
    package var sessions: [SessionMeta] = []
    package var isRefreshing = false

    package init(workspace: Workspace) {
      self.workspace = workspace
    }
  }

  package enum Action: Equatable {
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

  package init() {}

  @Dependency(\.openCodeConfiguration) var openCodeConfiguration
  @Dependency(\.portForwarding) var portForwarding
  @Dependency(\.openCodeAPIFactory) var openCodeAPIFactory

  package var body: some ReducerOf<Self> {
    Reduce(core)
      .ifLet(
        \.workspaceInteraction,
        action: \.workspaceInteraction
      ) {
        WorkspaceInteractionFeature()
      }
  }

  // swiftlint:disable:next cyclomatic_complexity
  package func core(state: inout State, action: Action) -> Effect<Action> {
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
      return handleOpenWorkspace(state: &state, id: id)

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
