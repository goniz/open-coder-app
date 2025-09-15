import ComposableArchitecture
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

    package init(workspace: Workspace, onlineState: WorkspaceOnlineState) {
      self.workspace = workspace
      self.onlineState = onlineState
    }
  }

  package enum Action: Equatable {
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
    case let .tabSelected(tab):
      state.selectedTab = tab
      return .none

    case .chat:
      return .none
    }
  }
}
