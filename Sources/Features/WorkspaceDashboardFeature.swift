import ComposableArchitecture
import Foundation
import Models

@Reducer
package struct WorkspaceDashboardFeature {
  package enum Tab: String, CaseIterable {
    case sessions = "Sessions"
    case repo = "Repo"
    case terminals = "Terminals"
    case activity = "Activity"
  }

  @ObservableState
  package struct State: Equatable {
    package var workspace: Workspace
    package var onlineState: WorkspaceOnlineState
    package var selectedTab: Tab = .sessions
    package var sessions: [SessionMeta] = []
    package var isRefreshing = false
    package var showingSpawningOverlay = false

    package init(workspace: Workspace, onlineState: WorkspaceOnlineState) {
      self.workspace = workspace
      self.onlineState = onlineState
    }
  }

  package enum Action: Equatable {
    case tabSelected(Tab)
    case refreshSessions
    case sessionsRefreshed([SessionMeta])
    case showLiveOutput
    case spawnPhaseUpdated(SpawnPhase)
    case cleanAndRetry
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .tabSelected(tab):
      state.selectedTab = tab
      if tab == .sessions {
        return .run { send in
          await send(.refreshSessions)
        }
      }
      return .none

    case .refreshSessions:
      state.isRefreshing = true
      let workspaceId = state.workspace.id
      return .run { send in
        // Mock refresh - in real implementation would fetch from server
        try await Task.sleep(for: .seconds(1))
        let mockSessions = Self.createMockSessions(for: workspaceId)
        await send(.sessionsRefreshed(mockSessions))
      }

    case let .sessionsRefreshed(sessions):
      state.sessions = sessions
      state.isRefreshing = false
      return .none

    case .showLiveOutput:
      return .none

    case let .spawnPhaseUpdated(phase):
      state.onlineState = .spawning(phase: phase)
      state.showingSpawningOverlay = true
      if case .attach = phase {
        state.showingSpawningOverlay = false
      }
      return .none

    case .cleanAndRetry:
      state.onlineState = .spawning(phase: .ssh)
      state.showingSpawningOverlay = true
      return .none
    }
  }

  private static func createMockSessions(for workspaceId: UUID) -> [SessionMeta] {
    [
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
      ),
      SessionMeta(
        id: "3",
        title: "Feature Implementation",
        lastMessagePreview: "Implemented new dashboard UI",
        updatedAt: Date().addingTimeInterval(-600),
        workspaceId: workspaceId
      ),
    ]
  }
}
