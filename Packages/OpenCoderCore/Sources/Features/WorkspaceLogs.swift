import Protocols
import Foundation
import Models

public enum WorkspaceLogsError: Swift.Error, LocalizedError, Equatable, Sendable {
  case missingConfiguration

  public var errorDescription: String? {
    switch self {
    case .missingConfiguration:
      return "No SSH server configuration linked to this workspace."
    }
  }
}

public enum WorkspaceLogs: Sendable {
  /// Returns a live AsyncStream of lines from the remote workspace's live log or tmux window.
  /// Falls back to an empty stream if no SSH configuration is linked to the workspace.
  public static func stream(for workspace: Workspace, window: String? = nil) -> AsyncStream<String> {
    guard let config = WorkspacesStorage.loadSSHConfigForWorkspace(workspace) else {
      return AsyncStream { continuation in
        continuation.yield("[Live Output] No SSH server configuration linked to this workspace.")
        continuation.finish()
      }
    }

    let service = WorkspaceService(config: config)
    return service.getLiveOutputStream(workspace: workspace, window: window)
  }

  /// Returns the available tmux window names for the workspace's session.
  public static func tmuxWindows(for workspace: Workspace) async throws -> [String] {
    guard let config = WorkspacesStorage.loadSSHConfigForWorkspace(workspace) else {
      throw WorkspaceLogsError.missingConfiguration
    }

    let service = WorkspaceService(config: config)
    return try await service.listTmuxWindows(workspace: workspace)
  }
}
