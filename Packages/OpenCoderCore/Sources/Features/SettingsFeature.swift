import ComposableArchitecture
import Models

@Reducer
public struct SettingsFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var theme: Theme = .system
    public var notificationsEnabled = true
    public var autoSaveEnabled = true
    public var showingLogs = false

    public init() {}
  }

  public enum Action: Equatable, BindableAction, Sendable {
    case binding(BindingAction<State>)
    case task
    case resetToDefaults
    case toggleLogs
    case clearLogs
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
    }
  }
}

public enum Theme: String, Equatable, CaseIterable, Sendable {
  case light
  case dark
  case system
}
