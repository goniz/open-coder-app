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
    let token = try await portForwarding.startForward(
      workspace: workspace,
      serverConfig: serverConfig,
      remotePort: remotePort
    )

    await send(.workspacePortForwardEstablished(workspaceID, token))
    await send(.spawnPhaseUpdated(workspaceID, .apiHandshake))

    guard let serverURL = URL(string: "http://127.0.0.1:\(token.localPort)") else {
      throw SSHError.connectionFailed("Failed to create server URL")
    }

    let apiConfiguration = OpenCodeConfiguration(
      serverURL: serverURL,
      timeout: openCodeConfiguration.timeout,
      retryCount: openCodeConfiguration.retryCount
    )

    let apiClient = openCodeAPIFactory.make(apiConfiguration)

    _ = try await apiClient.getConfig()

    return token.localPort
  }
}
