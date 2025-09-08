import ComposableArchitecture
import DependencyClients
import Foundation
import Models

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

  package init(configuration: SSHServerConfiguration) {
    self.configuration = configuration
  }
}

@Reducer
package struct ServersFeature {
  @ObservableState
  package struct State: Equatable {
    package var servers: [ServerState] = []
    package var isLoading = false
    package var isAddingServer = false

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
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
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
    return .none
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
}
