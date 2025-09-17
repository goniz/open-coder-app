import ComposableArchitecture
import DependencyClients
import Foundation
import Models

enum WorkspacesFeatureHandlers {
  static func handleOpenWorkspace(workspace: Workspace, id: UUID) -> Effect<WorkspacesFeature.Action> {
    .run { send in
      do {
        // Get SSH configuration from linked server
        guard let config = WorkspacesStorage.loadSSHConfigForWorkspace(workspace) else {
          let errorMessage =
            "No SSH server configuration found for this workspace. "
            + "Please associate this workspace with a server."
          await send(.workspaceOpened(id, .failure(.connectionFailed(errorMessage))))
          return
        }

        // Simplified connect: only establish SSH and ensure tmux session exists.
        print(
          "🔗 Simple connect to \(workspace.user)@\(workspace.host) using server: \(config.name)")

        let workspaceService = WorkspaceService(config: config)
        try await workspaceService.connectAndEnsureTmux(workspace: workspace)

        // Mark as online without a port (use 0 to denote 'no app port').
        await send(.workspaceOpened(id, .success(.init(port: 0, online: true, error: nil))))
      } catch {
        // Log the error for debugging
        print("❌ SSH connection failed: \(error.localizedDescription)")

        if let sshError = error as? SSHError {
          await send(.workspaceOpened(id, .failure(sshError)))
        } else {
          let errorMessage =
            "SSH connection failed: \(error.localizedDescription). "
            + "Check that SSH credentials are configured for this server."
          await send(.workspaceOpened(id, .failure(.connectionFailed(errorMessage))))
        }
      }
    }
  }

  static func handleWorkspaceOpened(
    state: inout WorkspacesFeature.WorkspaceState,
    id: UUID,
    result: Result<WorkspaceService.SpawnResult, SSHError>
  ) -> Effect<WorkspacesFeature.Action> {
    switch result {
    case .success(let spawnResult):
      if spawnResult.online {
        state.onlineState = .online(port: spawnResult.port)
        state.lastConnectedAt = Date()

        // For simple SSH+tmux connect (port == 0), skip extra follow-up actions.
        if spawnResult.port == 0 {
          return .none
        } else {
          // For full spawn flow, fetch sessions after successful connection
          return .run { send in
            await send(.refreshWorkspace(id))
          }
        }
      } else {
        state.onlineState = .error(spawnResult.error?.localizedDescription ?? "Unknown error")
      }
    case .failure(let error):
      state.onlineState = .error(error.localizedDescription)
    }

    return .none
  }

  static func handleCleanAndRetry(workspace: Workspace, id: UUID) -> Effect<WorkspacesFeature.Action> {
    .run { send in
      do {
        // Get SSH configuration from linked server
        guard let config = WorkspacesStorage.loadSSHConfigForWorkspace(workspace) else {
          let errorMessage =
            "No SSH server configuration found for this workspace. "
            + "Please associate this workspace with a server."
          await send(.workspaceOpened(id, .failure(.connectionFailed(errorMessage))))
          return
        }

        // Log the retry attempt for debugging
        print(
          "🔄 Retrying SSH connection to \(workspace.user)@\(workspace.host) using server: \(config.name)")

        let workspaceService = WorkspaceService(config: config)
        let result = try await workspaceService.cleanAndRetry(workspace: workspace)
        await send(.workspaceOpened(id, .success(result)))
      } catch {
        // Log the error for debugging
        print("❌ SSH retry failed: \(error.localizedDescription)")

        if let sshError = error as? SSHError {
          await send(.workspaceOpened(id, .failure(sshError)))
        } else {
          let errorMessage =
            "SSH connection failed: \(error.localizedDescription). "
            + "Check that SSH credentials are configured for this server."
          await send(.workspaceOpened(id, .failure(.connectionFailed(errorMessage))))
        }
      }
    }
  }
}
