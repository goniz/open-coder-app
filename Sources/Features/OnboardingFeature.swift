import ComposableArchitecture
import DependencyClients
import Foundation
import Models

@Reducer
package struct OnboardingFeature {
  @ObservableState
  package struct State: Equatable {
    package var serverConfiguration = SSHServerConfiguration()
    package var isConnecting = false
    package var connectionError: String?
    package var showPassword = false

    package init() {}
  }

  package enum Action: Equatable, BindableAction {
    case binding(BindingAction<State>)
    case togglePasswordVisibility
    case toggleAuthenticationMethod
    case connectButtonTapped
    case connectionSuccess
    case connectionFailure(String)
    case skipOnboarding
    case completeOnboarding
  }

  package struct ConnectionError: Error, Equatable {
    package let message: String

    package init(_ message: String) {
      self.message = message
    }
  }

  package init() {}

  package var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce(core)
  }

  package func core(state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .binding:
      state.connectionError = nil
      return .none

    case .togglePasswordVisibility:
      state.showPassword.toggle()
      return .none

    case .toggleAuthenticationMethod:
      state.serverConfiguration.useKeyAuthentication.toggle()
      state.serverConfiguration.password = ""
      state.serverConfiguration.privateKeyPath = ""
      return .none

    case .connectButtonTapped:
      guard state.serverConfiguration.isValid else {
        state.connectionError = "Please fill in all required fields"
        return .none
      }

      state.isConnecting = true
      state.connectionError = nil

      return .run { [config = state.serverConfiguration] send in
        do {
          try await testSSHConnection(config)
          await send(.connectionSuccess)
        } catch {
          let message = (error as? ConnectionError)?.message ?? error.localizedDescription
          await send(.connectionFailure(message))
        }
      }

    case .connectionSuccess:
      state.isConnecting = false
      return .run { [config = state.serverConfiguration] send in
        await saveServerConfigurationAsync(config)
        await send(.completeOnboarding)
      }

    case let .connectionFailure(message):
      state.isConnecting = false
      state.connectionError = message
      return .none

    case .skipOnboarding, .completeOnboarding:
      return .none
    }
  }

  private func testSSHConnection(_ config: SSHServerConfiguration) async throws {
    guard !config.host.isEmpty, !config.username.isEmpty else {
      throw ConnectionError("Invalid configuration: Host and username are required")
    }

    if config.useKeyAuthentication && config.privateKeyPath.isEmpty {
      throw ConnectionError("Private key path is required for key authentication")
    }

    if !config.useKeyAuthentication && config.password.isEmpty {
      throw ConnectionError("Password is required for password authentication")
    }

    do {
      try await SSHClient.testConnection(config)
    } catch let error as SSHConnectionError {
      throw ConnectionError(error.localizedDescription)
    } catch {
      throw ConnectionError("Connection failed: \(error.localizedDescription)")
    }
  }

  private func saveServerConfigurationAsync(_ config: SSHServerConfiguration) async {
    await Task.detached {
      guard let data = UserDefaults.standard.data(forKey: "savedServers") else {
        await saveNewServerConfigurationAsync(config)
        return
      }

      do {
        var existingConfigs = try JSONDecoder().decode([SSHServerConfiguration].self, from: data)
        let isDuplicate = existingConfigs.contains { existing in
          existing.host == config.host && existing.username == config.username && existing.port == config.port
        }
        if !isDuplicate {
          existingConfigs.append(config)
          let updatedData = try JSONEncoder().encode(existingConfigs)
          UserDefaults.standard.set(updatedData, forKey: "savedServers")
        }
      } catch {
        print("Failed to update saved servers: \(error)")
        await saveNewServerConfigurationAsync(config)
      }
    }.value
  }

  private func saveNewServerConfigurationAsync(_ config: SSHServerConfiguration) async {
    await Task.detached {
      do {
        let data = try JSONEncoder().encode([config])
        UserDefaults.standard.set(data, forKey: "savedServers")
      } catch {
        print("Failed to save server configuration: \(error)")
      }
    }.value
  }
}
