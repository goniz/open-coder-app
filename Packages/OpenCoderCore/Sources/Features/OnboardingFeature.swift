import ComposableArchitecture
import Protocols
import Implementations
import Foundation
import Models

@Reducer
public struct OnboardingFeature: Sendable {
  @ObservableState
  public struct State: Equatable, Sendable {
    public var serverConfiguration = SSHServerConfiguration()
    public var isConnecting = false
    public var connectionError: String?
    public var showPassword = false

    public init() {}
  }

  public enum Action: Equatable, BindableAction, Sendable {
    case binding(BindingAction<State>)
    case togglePasswordVisibility
    case toggleAuthenticationMethod
    case connectButtonTapped
    case connectionSuccess
    case connectionFailure(String)
    case skipOnboarding
    case completeOnboarding
  }

  public struct ConnectionError: Swift.Error, LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
      self.message = message
    }

    public var errorDescription: String? {
      message
    }
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce(core)
  }

  public func core(state: inout State, action: Action) -> Effect<Action> {
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
        await Task.detached {
          do {
            try await testSSHConnection(config)
            await send(.connectionSuccess)
          } catch {
            let message = (error as? ConnectionError)?.message ?? error.localizedDescription
            await send(.connectionFailure(message))
          }
        }.value
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
          existing.host == config.host && existing.username == config.username
            && existing.port == config.port
        }
        if !isDuplicate {
          existingConfigs.append(config)
          let updatedData = try JSONEncoder().encode(existingConfigs)
          UserDefaults.standard.set(updatedData, forKey: "savedServers")
        }
      } catch {
        await AppLogger.shared.log(
          "Failed to update saved servers: \(error)",
          level: .error,
          category: .ssh
        )
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
        await AppLogger.shared.log(
          "Failed to save server configuration: \(error)",
          level: .error,
          category: .ssh
        )
      }
    }.value
  }
}
