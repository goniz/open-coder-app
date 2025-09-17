import ComposableArchitecture
import DependencyClients
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

    package init() {}
  }

  package struct WorkspaceState: Equatable, Identifiable {
    package let id = UUID()
    package var workspace: Workspace
    package var onlineState: WorkspaceOnlineState = .idle
    package var lastConnectedAt: Date?
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
    case workspaceRefreshed(WorkspaceState.ID, [SessionMeta])
    case removeWorkspace(WorkspaceState.ID)
    case dismissAddWorkspace
    case showLiveOutput(WorkspaceState.ID)
    case cleanAndRetry(WorkspaceState.ID)
    case spawnPhaseUpdated(WorkspaceState.ID, SpawnPhase)
    case hideWorkspaceInteraction
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    Reduce(core)
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

    case let .workspaceRefreshed(id, sessions):
      return handleWorkspaceRefreshed(state: &state, id: id, sessions: sessions)

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

    case .hideWorkspaceInteraction:
      return handleHideWorkspaceInteraction(state: &state)
    }
  }

  private func handleWorkspacesLoaded(state: inout State, workspaces: [WorkspaceState]) -> Effect<
    Action
  > {
    // Preserve online state and metadata when reloading from storage
    let existingByID: [UUID: WorkspaceState] = Dictionary(
      uniqueKeysWithValues: state.workspaces.map { ($0.workspace.id, $0) }
    )

    state.workspaces = workspaces.map { loaded in
      var merged = loaded
      if let existing = existingByID[loaded.workspace.id] {
        merged.onlineState = existing.onlineState
        merged.lastConnectedAt = existing.lastConnectedAt
        merged.sessions = existing.sessions
        merged.isRefreshing = existing.isRefreshing
      }
      return merged
    }
    state.isLoading = false
    return .none
  }

  private func handleAddWorkspace(state: inout State) -> Effect<Action> {
    state.isAddingWorkspace = true
    return .none
  }

  private func handleAddWorkspaceCompleted(state: inout State, workspace: Workspace) -> Effect<
    Action
  > {
    let workspaceState = WorkspaceState(workspace: workspace)
    state.workspaces.append(workspaceState)
    state.isAddingWorkspace = false
    WorkspacesStorage.saveWorkspacesToStorage(state.workspaces.map { $0.workspace })
    return .none
  }

  private func handleRemoveWorkspace(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
    state.workspaces.removeAll { $0.id == id }
    WorkspacesStorage.saveWorkspacesToStorage(state.workspaces.map { $0.workspace })
    return .none
  }

  private func handleDismissAddWorkspace(state: inout State) -> Effect<Action> {
    state.isAddingWorkspace = false
    return .none
  }

  private func handleShowLiveOutput(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
    state.selectedWorkspace = id
    state.interactionInitialTab = .liveOutput
    state.showingWorkspaceInteraction = true
    return .none
  }

  private func handleTask(state: inout State) -> Effect<Action> {
    state.isLoading = true
    return .run { send in
      let workspaces = WorkspacesStorage.loadWorkspacesFromStorage()
      let workspaceStates = workspaces.map { WorkspaceState(workspace: $0) }
      await send(.workspacesLoaded(workspaceStates))
    }
  }

  private func handleOpenWorkspace(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
    guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }

    state.workspaces[index].onlineState = .spawning(phase: .ssh)
    state.selectedWorkspace = id
    state.interactionInitialTab = .activity
    state.showingWorkspaceInteraction = true
    let workspace = state.workspaces[index].workspace

    return WorkspacesFeatureHandlers.handleOpenWorkspace(workspace: workspace, id: id)
  }

  private func handleWorkspaceOpened(
    state: inout State,
    id: WorkspaceState.ID,
    result: Result<WorkspaceService.SpawnResult, SSHError>
  ) -> Effect<Action> {
    guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }
    return WorkspacesFeatureHandlers.handleWorkspaceOpened(
      state: &state.workspaces[index], id: id, result: result
    )
  }

  private func handleHideWorkspaceInteraction(state: inout State) -> Effect<Action> {
    state.showingWorkspaceInteraction = false
    state.selectedWorkspace = nil
    state.interactionInitialTab = .activity
    return .none
  }

  private func handleRefreshWorkspace(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
    guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }
    guard case .online = state.workspaces[index].onlineState else { return .none }

    state.workspaces[index].isRefreshing = true
    let workspaceId = state.workspaces[index].workspace.id

    return .run { send in
      // Mock session fetch - in real implementation would fetch from server
      try await Task.sleep(for: .seconds(1))
      let mockSessions = [
        SessionMeta(
          id: "1",
          title: "Code Review",
          lastMessagePreview: "Added new feature for workspace management",
          updatedAt: Date(),
          workspaceId: workspaceId
        ),
        SessionMeta(
          id: "2",
          title: "Bug Fix",
          lastMessagePreview: "Fixed SSH connection issue",
          updatedAt: Date().addingTimeInterval(-300),
          workspaceId: workspaceId
        )
      ]
      await send(.workspaceRefreshed(id, mockSessions))
    }
  }

  private func handleWorkspaceRefreshed(
    state: inout State,
    id: WorkspaceState.ID,
    sessions: [SessionMeta]
  ) -> Effect<Action> {
    guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }

    state.workspaces[index].sessions = sessions
    state.workspaces[index].isRefreshing = false

    return .none
  }

  private func handleCleanAndRetry(state: inout State, id: WorkspaceState.ID) -> Effect<Action> {
    guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }

    state.workspaces[index].onlineState = .spawning(phase: .ssh)
    let workspace = state.workspaces[index].workspace

    return WorkspacesFeatureHandlers.handleCleanAndRetry(workspace: workspace, id: id)
  }

  private func handleSpawnPhaseUpdated(
    state: inout State,
    id: WorkspaceState.ID,
    phase: SpawnPhase
  ) -> Effect<Action> {
    guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return .none }

    state.workspaces[index].onlineState = .spawning(phase: phase)

    return .none
  }

}
