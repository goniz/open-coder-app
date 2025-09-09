import ComposableArchitecture
import DependencyClients
import Models

@Reducer
package struct HomeFeature {
  @ObservableState
  package struct State: Equatable {
    package var selectedTab: Tab = .servers
    package var servers = ServersFeature.State()
    package var projects = ProjectsFeature.State()
    package var chat = ChatFeature.State()
    package var settings = SettingsFeature.State()

    package init() {}
  }

  package enum Action: Equatable {
    case tabSelected(Tab)
    case servers(ServersFeature.Action)
    case projects(ProjectsFeature.Action)
    case chat(ChatFeature.Action)
    case settings(SettingsFeature.Action)
  }

  package enum Tab: Equatable {
    case servers
    case projects
    case chat
    case settings
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    Scope(state: \.servers, action: \.servers) {
      ServersFeature()
    }
    Scope(state: \.projects, action: \.projects) {
      ProjectsFeature()
    }
    Scope(state: \.chat, action: \.chat) {
      ChatFeature()
    }
    Scope(state: \.settings, action: \.settings) {
      SettingsFeature()
    }
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .tabSelected(tab):
      state.selectedTab = tab
      return .none

    case .servers(.task), .projects(.task), .chat(.task), .settings(.task):
      return .none

    case .servers, .projects, .chat, .settings:
      return .none
    }
  }
}
