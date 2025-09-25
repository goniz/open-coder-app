import Dependencies
import Foundation
import Models

public struct PortForwardToken: Equatable, Sendable {
  public let id: UUID
  public let localPort: Int
  public let remotePort: Int

  public init(id: UUID = UUID(), localPort: Int, remotePort: Int) {
    self.id = id
    self.localPort = localPort
    self.remotePort = remotePort
  }
}

public protocol PortForwardingClient: Sendable {
  func startForward(
    workspace: Workspace,
    serverConfig: SSHServerConfiguration,
    remotePort: Int
  ) async throws -> PortForwardToken

  func stopForward(_ token: PortForwardToken) async
}

public enum PortForwardingClientKey: DependencyKey, Sendable {
  public static let liveValue: PortForwardingClient = LivePortForwardingClient()
  public static let testValue: PortForwardingClient = UnimplementedPortForwardingClient()
}

extension DependencyValues {
  public var portForwarding: PortForwardingClient {
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
