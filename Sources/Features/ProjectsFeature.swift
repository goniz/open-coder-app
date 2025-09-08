import ComposableArchitecture
import Foundation

@Reducer
package struct ProjectsFeature {
  @ObservableState
  package struct State: Equatable {
    package var projects: [Project] = []
    package var isLoading = false

    package init() {}
  }

  package enum Action: Equatable {
    case task
    case projectsLoaded([Project])
    case addProject
    case removeProject(Int)
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      state.isLoading = true
      return .run { send in
        // TODO: Load projects from storage
        await send(.projectsLoaded([]))
      }

    case let .projectsLoaded(projects):
      state.projects = projects
      state.isLoading = false
      return .none

    case .addProject:
      // TODO: Navigate to add project screen
      return .none

    case let .removeProject(index):
      state.projects.remove(at: index)
      return .none
    }
  }
}

// TODO: Define Project model
package struct Project: Equatable, Identifiable {
  package let id: UUID
  package let name: String
  package let path: String
}