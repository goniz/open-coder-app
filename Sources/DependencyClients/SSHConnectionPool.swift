import Foundation
import Models

// A simple shared pool of SSHConnectionManager instances keyed by server configuration ID.
// This lets different features reuse the same underlying SSH connection.
package actor SSHConnectionPool {
  package static let shared = SSHConnectionPool()

  private var managers: [UUID: SSHConnectionManager] = [:]

  // Returns a connection manager for the given server config, creating one if needed.
  package func manager(for config: SSHServerConfiguration) -> SSHConnectionManager {
    if let existing = managers[config.id] { return existing }
    let created = SSHConnectionManager(config: config)
    managers[config.id] = created
    return created
  }

  // Establishes a connection for the given server config and keeps the manager cached.
  package func connect(_ config: SSHServerConfiguration) async throws {
    let mgr = manager(for: config)
    _ = try await mgr.withConnection { _ in () }
  }

  // Closes and removes the connection manager for a given server ID.
  package func disconnect(serverConfigID: UUID) async {
    if let mgr = managers[serverConfigID] {
      await mgr.disconnect()
      managers.removeValue(forKey: serverConfigID)
    }
  }

  // Returns whether the connection is currently active/healthy for a given server config ID.
  package func isConnected(serverConfigID: UUID) async -> Bool {
    guard let mgr = managers[serverConfigID] else { return false }
    return await mgr.isConnected()
  }
}
