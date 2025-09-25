import ComposableArchitecture
import Foundation

@Reducer
public struct ProjectsFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var projects: [Project] = []
    public var isLoading = false

    public init() {}
  }

  public enum Action: Equatable, Sendable {
    case task
    case projectsLoaded([Project])
    case addProject
    case removeProject(Int)
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce(core)
  }

  public func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      state.isLoading = true
      return .run { send in
        await send(.projectsLoaded([]))
      }

    case let .projectsLoaded(projects):
      state.projects = projects
      state.isLoading = false
      return .none

    case .addProject:
      return .none

    case let .removeProject(index):
      state.projects.remove(at: index)
      return .none
    }
  }
}

public struct Project: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let path: String
}
