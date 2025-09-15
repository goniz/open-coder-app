import Foundation
import Models
import DependencyClients

package enum WorkspaceLogs {
  /// Returns a live AsyncStream of lines from the remote workspace's live log.
  /// Falls back to an empty stream if no SSH configuration is linked to the workspace.
  package static func stream(for workspace: Workspace) -> AsyncStream<String> {
    guard let config = WorkspacesStorage.loadSSHConfigForWorkspace(workspace) else {
      return AsyncStream { continuation in
        continuation.yield("[Live Output] No SSH server configuration linked to this workspace.")
        continuation.finish()
      }
    }

    let service = WorkspaceService(config: config)
    return service.getLiveOutputStream(workspace: workspace)
  }
}
