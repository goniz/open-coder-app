import ComposableArchitecture
import Protocols
import Foundation
import Models

extension WorkspacesFeature {
  internal func performForwardingAndHandshake(
    workspace: Workspace,
    workspaceID: WorkspaceState.ID,
    serverConfig: SSHServerConfiguration,
    remotePort: Int,
    send: @escaping @Sendable (Action) async -> Void
  ) async throws -> Int {
    await send(.spawnPhaseUpdated(workspaceID, .portForwarding))

    guard !Task.isCancelled else {
      throw SSHError.connectionFailed("Port forwarding cancelled")
    }

    let token: PortForwardToken
    do {
      token = try await portForwarding.startForward(
        workspace: workspace,
        serverConfig: serverConfig,
        remotePort: remotePort
      )
    } catch {
      await AppLogger.shared.log(
        "Port forwarding failed for workspace \(workspace.name): \(error)",
        level: .error,
        category: .workspace
      )
      throw SSHError.connectionFailed("Port forwarding failed: \(error.localizedDescription)")
    }

    await send(.workspacePortForwardEstablished(workspaceID, token))
    await send(.spawnPhaseUpdated(workspaceID, .apiHandshake))

    guard !Task.isCancelled else {
      throw SSHError.connectionFailed("API handshake cancelled")
    }

    guard let serverURL = URL(string: "http://127.0.0.1:\(token.localPort)") else {
      await AppLogger.shared.log(
        "Invalid server URL for port \(token.localPort)",
        level: .error,
        category: .workspace
      )
      throw SSHError.connectionFailed("Failed to create server URL for port \(token.localPort)")
    }

    let apiConfiguration = OpenCodeConfiguration(
      serverURL: serverURL,
      timeout: openCodeConfiguration.timeout,
      retryCount: openCodeConfiguration.retryCount
    )

    let apiClient = openCodeAPIFactory.make(apiConfiguration)

    do {
      _ = try await apiClient.getConfig()
    } catch {
      await AppLogger.shared.log(
        "API handshake failed for workspace \(workspace.name): \(error)",
        level: .error,
        category: .workspace
      )
      throw SSHError.connectionFailed("API handshake failed: \(error.localizedDescription)")
    }

    return token.localPort
  }
}
