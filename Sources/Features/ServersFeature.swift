import ComposableArchitecture
import DependencyClients
import Foundation
import Models

#if canImport(UIKit)
import UIKit
#endif

package enum ConnectionState: Equatable {
  case disconnected
  case connecting
  case connected
  case error(String)
}

package struct ServerState: Equatable, Identifiable {
  package let id = UUID()
  package var configuration: SSHServerConfiguration
  package var connectionState: ConnectionState = .disconnected
  package var lastConnectedAt: Date?

  package var shouldMaintainConnection: Bool {
    get { configuration.shouldMaintainConnection }
    set { configuration.shouldMaintainConnection = newValue }
  }

  package init(configuration: SSHServerConfiguration) {
    self.configuration = configuration
  }
}

@Reducer
// swiftlint:disable:next type_body_length
package struct ServersFeature {
  @ObservableState
  package struct State: Equatable {
    package var servers: [ServerState] = []
    package var isLoading = false
    package var isAddingServer = false
    package var persistentConnections: Set<ServerState.ID> = []
    package var isInBackground = false
    package var activeTaskConnections: [ServerState.ID: Date] = [:]
    package var activeTasks: [CodingTask.ID: CodingTask] = [:]
    #if canImport(UIKit) && !os(macOS)
    package var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #else
    package var backgroundTaskID: Int = -1
    #endif

    package init() {}
  }

  package enum Action: Equatable {
    case task
    case serversLoaded([ServerState])
    case addServer
    case addServerCompleted(SSHServerConfiguration)
    case testConnection(ServerState.ID)
    case connectionSuccess(ServerState.ID)
    case connectionFailed(ServerState.ID, String)
    case removeServer(ServerState.ID)
    case dismissAddServer
    case toggleConnectionPersistence(ServerState.ID)
    case appDidEnterBackground
    case appWillEnterForeground
    case maintainPersistentConnections
    case startTaskMonitoring(CodingTask)
    case stopTaskMonitoring(CodingTask.ID)
    case taskProgressUpdate(CodingTask.ID, Double, String)
    case maintainActiveTaskConnections
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task, .serversLoaded, .addServer, .addServerCompleted, .testConnection,
         .connectionSuccess, .connectionFailed, .removeServer, .dismissAddServer, .toggleConnectionPersistence:
      return handleServerAction(state: &state, action: action)
    case .appDidEnterBackground, .appWillEnterForeground, .maintainPersistentConnections:
      return handleConnectionAction(state: &state, action: action)
    case .startTaskMonitoring, .stopTaskMonitoring, .taskProgressUpdate, .maintainActiveTaskConnections:
      return handleTaskAction(state: &state, action: action)
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  private func handleServerAction(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .task:
      return handleTask(state: &state)
    case let .serversLoaded(servers):
      return handleServersLoaded(state: &state, servers: servers)
    case .addServer:
      return handleAddServer(state: &state)
    case let .addServerCompleted(config):
      return handleAddServerCompleted(state: &state, config: config)
    case let .testConnection(id):
      return handleTestConnection(state: &state, id: id)
    case let .connectionSuccess(id):
      return handleConnectionSuccess(state: &state, id: id)
    case let .connectionFailed(id, errorMessage):
      return handleConnectionFailed(state: &state, id: id, errorMessage: errorMessage)
    case let .removeServer(id):
      return handleRemoveServer(state: &state, id: id)
    case .dismissAddServer:
      return handleDismissAddServer(state: &state)
    case let .toggleConnectionPersistence(id):
      return handleToggleConnectionPersistence(state: &state, id: id)
    default:
      return .none
    }
  }

  private func handleConnectionAction(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .appDidEnterBackground:
      return handleAppDidEnterBackground(state: &state)
    case .appWillEnterForeground:
      return handleAppWillEnterForeground(state: &state)
    case .maintainPersistentConnections:
      return handleMaintainPersistentConnections(state: &state)
    default:
      return .none
    }
  }

  private func handleTaskAction(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case let .startTaskMonitoring(task):
      return handleStartTaskMonitoring(state: &state, task: task)
    case let .stopTaskMonitoring(taskID):
      return handleStopTaskMonitoring(state: &state, taskID: taskID)
    case let .taskProgressUpdate(taskID, progress, step):
      return handleTaskProgressUpdate(state: &state, taskID: taskID, progress: progress, step: step)
    case .maintainActiveTaskConnections:
      return handleMaintainActiveTaskConnections(state: &state)
    default:
      return .none
    }
  }

  private func handleTask(state: inout State) -> Effect<Action> {
    state.isLoading = true
    return .run { send in
      let servers = loadServersFromStorage()
      await send(.serversLoaded(servers))
    }
  }

  private func handleServersLoaded(state: inout State, servers: [ServerState]) -> Effect<Action> {
    state.servers = servers
    state.isLoading = false

    state.persistentConnections = Set(servers.compactMap { server in
      server.shouldMaintainConnection ? server.id : nil
    })

    return .run { send in
      await send(.maintainPersistentConnections)
    }
  }

  private func handleAddServer(state: inout State) -> Effect<Action> {
    state.isAddingServer = true
    return .none
  }

  private func handleAddServerCompleted(state: inout State, config: SSHServerConfiguration) -> Effect<Action> {
    let serverState = ServerState(configuration: config)
    state.servers.append(serverState)
    state.isAddingServer = false
    saveServersToStorage(state.servers)
    return .none
  }

  private func handleTestConnection(state: inout State, id: ServerState.ID) -> Effect<Action> {
    guard let index = state.servers.firstIndex(where: { $0.id == id }) else { return .none }
    state.servers[index].connectionState = .connecting
    let config = state.servers[index].configuration

    return .run { send in
      do {
        try await SSHClient.testConnection(config)
        await send(.connectionSuccess(id))
      } catch {
        await send(.connectionFailed(id, error.localizedDescription))
      }
    }
  }

  private func handleConnectionSuccess(state: inout State, id: ServerState.ID) -> Effect<Action> {
    guard let index = state.servers.firstIndex(where: { $0.id == id }) else { return .none }
    state.servers[index].connectionState = .connected
    state.servers[index].lastConnectedAt = Date()

    if state.servers[index].shouldMaintainConnection {
      state.persistentConnections.insert(id)
    }

    return .none
  }

  private func handleConnectionFailed(state: inout State, id: ServerState.ID, errorMessage: String) -> Effect<Action> {
    guard let index = state.servers.firstIndex(where: { $0.id == id }) else { return .none }
    state.servers[index].connectionState = .error(errorMessage)
    return .none
  }

  private func handleRemoveServer(state: inout State, id: ServerState.ID) -> Effect<Action> {
    state.servers.removeAll { $0.id == id }
    saveServersToStorage(state.servers)
    return .none
  }

  private func handleDismissAddServer(state: inout State) -> Effect<Action> {
    state.isAddingServer = false
    return .none
  }

  private func loadServersFromStorage() -> [ServerState] {
    guard let data = UserDefaults.standard.data(forKey: "savedServers") else { return [] }
    do {
      let configurations = try JSONDecoder().decode([SSHServerConfiguration].self, from: data)
      return configurations.map { ServerState(configuration: $0) }
    } catch {
      print("Failed to load servers: \(error)")
      return []
    }
  }

  private func saveServersToStorage(_ servers: [ServerState]) {
    let configurations = servers.map { $0.configuration }
    do {
      let data = try JSONEncoder().encode(configurations)
      UserDefaults.standard.set(data, forKey: "savedServers")
    } catch {
      print("Failed to save servers: \(error)")
    }
  }

  private func handleToggleConnectionPersistence(state: inout State, id: ServerState.ID) -> Effect<Action> {
    guard let index = state.servers.firstIndex(where: { $0.id == id }) else { return .none }
    state.servers[index].shouldMaintainConnection.toggle()

    if state.servers[index].shouldMaintainConnection {
      if state.servers[index].connectionState == .connected {
        state.persistentConnections.insert(id)
      }
    } else {
      state.persistentConnections.remove(id)
    }

    saveServersToStorage(state.servers)
    return .none
  }

  private func handleAppDidEnterBackground(state: inout State) -> Effect<Action> {
    state.isInBackground = true
    return .none
  }

  private func handleAppWillEnterForeground(state: inout State) -> Effect<Action> {
    state.isInBackground = false
    return .run { send in
      await send(.maintainPersistentConnections)
    }
  }

  private func handleMaintainPersistentConnections(state: inout State) -> Effect<Action> {
    let reconnectEffects = state.persistentConnections.compactMap { id -> Effect<Action>? in
      guard let serverIndex = state.servers.firstIndex(where: { $0.id == id }),
            state.servers[serverIndex].connectionState != .connected else { return nil }

      return .run { send in
        await send(.testConnection(id))
      }
    }

    return .merge(reconnectEffects)
  }

  private func handleStartTaskMonitoring(state: inout State, task: CodingTask) -> Effect<Action> {
    state.activeTasks[task.id] = task
    state.activeTaskConnections[task.serverID] = Date()

    @Dependency(\.backgroundTask) var backgroundTask
    let taskId = task.id

    return .run { send in
      let backgroundTaskID = await backgroundTask.beginBackgroundTask("task-monitoring-\(taskId)")

      // Keep connection alive with periodic maintenance
      while true {
        try? await Task.sleep(for: .seconds(30))
        await send(.maintainActiveTaskConnections)
      }

      await backgroundTask.endBackgroundTask(backgroundTaskID)
    }
  }

  private func handleStopTaskMonitoring(state: inout State, taskID: CodingTask.ID) -> Effect<Action> {
    guard let task = state.activeTasks[taskID] else { return .none }

    state.activeTasks.removeValue(forKey: taskID)

    let hasOtherActiveTasks = state.activeTasks.values.contains { $0.serverID == task.serverID }

    if !hasOtherActiveTasks {
      state.activeTaskConnections.removeValue(forKey: task.serverID)
    }

    return .none
  }

  private func handleTaskProgressUpdate(
    state: inout State,
    taskID: CodingTask.ID,
    progress: Double,
    step: String
  ) -> Effect<Action> {
    guard var task = state.activeTasks[taskID] else { return .none }

    task.progress = progress
    task.currentStep = step
    state.activeTasks[taskID] = task

    return .none
  }

  private func handleMaintainActiveTaskConnections(state: inout State) -> Effect<Action> {
    let connectionEffects = state.activeTaskConnections.keys.map { _ in
      Effect<Action>.run { _ in

      }
    }

    return .merge(connectionEffects)
  }
}
