import Dependencies
import Foundation
import Models

package struct PortForwardToken: Equatable, Sendable {
  package let id: UUID
  package let localPort: Int
  package let remotePort: Int

  package init(id: UUID = UUID(), localPort: Int, remotePort: Int) {
    self.id = id
    self.localPort = localPort
    self.remotePort = remotePort
  }
}

package protocol PortForwardingClient: Sendable {
  func startForward(
    workspace: Workspace,
    serverConfig: SSHServerConfiguration,
    remotePort: Int
  ) async throws -> PortForwardToken

  func stopForward(_ token: PortForwardToken) async
}

package enum PortForwardingClientKey: DependencyKey {
  package static let liveValue: PortForwardingClient = LivePortForwardingClient()
  package static let testValue: PortForwardingClient = UnimplementedPortForwardingClient()
}

extension DependencyValues {
  package var portForwarding: PortForwardingClient {
    get { self[PortForwardingClientKey.self] }
    set { self[PortForwardingClientKey.self] = newValue }
  }
}

private struct UnimplementedPortForwardingClient: PortForwardingClient {
  func startForward(
    workspace: Workspace,
    serverConfig: SSHServerConfiguration,
    remotePort: Int
  ) async throws -> PortForwardToken {
    throw SSHError.connectionFailed("Port forwarding client not configured")
  }

  func stopForward(_ token: PortForwardToken) async {}
}
