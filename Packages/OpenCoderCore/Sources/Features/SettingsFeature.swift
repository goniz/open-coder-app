import ComposableArchitecture
import Foundation
import Models

@Reducer
public struct SettingsFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var theme: Theme = .system
    public var notificationsEnabled = true
    public var autoSaveEnabled = true
    public var thinkingBlocksEnabled = true
    public var showingLogs = false
    public var showingPreviousLogs = false
    public var logsFileURL: URL?

    public init() {}
  }

  public enum Action: Equatable, BindableAction, Sendable {
    case binding(BindingAction<State>)
    case task
    case resetToDefaults
    case toggleLogs
    case clearLogs
    case togglePreviousLogs
    case clearPreviousLogs
    case exportLogs
    case logsFileGenerated(URL?)
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce(core)
  }

  public func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .binding:
      return .none

    case .task:
      return .run { _ in
      }

    case .resetToDefaults:
      state = State()
      return .none

    case .toggleLogs:
      state.showingLogs.toggle()
      return .none

    case .clearLogs:
      return .run { _ in
        await AppLogger.shared.clearLogs()
      }

    case .togglePreviousLogs:
      state.showingPreviousLogs.toggle()
      return .none

    case .clearPreviousLogs:
      return .run { _ in
        await AppLogger.shared.clearPreviousLogs()
      }

    case .exportLogs:
      return .run { send in
        let url = await AppLogger.shared.exportLogsToFile()
        await send(.logsFileGenerated(url))
      }

    case .logsFileGenerated(let url):
      state.logsFileURL = url
      return .none
    }
  }
}

public enum Theme: String, Equatable, CaseIterable, Sendable {
  case light
  case dark
  case system
}
