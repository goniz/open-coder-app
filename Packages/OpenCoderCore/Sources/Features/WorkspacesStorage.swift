import Foundation
import Models

enum WorkspacesStorage {
  static func loadWorkspacesFromStorage() -> [Workspace] {
    guard let data = UserDefaults.standard.data(forKey: "savedWorkspaces") else { return [] }
    do {
      let workspaces = try JSONDecoder().decode([Workspace].self, from: data)
      return workspaces
    } catch {
      Task {
        await AppLogger.shared.log(
          "Failed to load workspaces: \(error)",
          level: .error,
          category: .workspace
        )
      }
      return []
    }
  }

  static func saveWorkspacesToStorage(_ workspaces: [Workspace]) {
    do {
      let data = try JSONEncoder().encode(workspaces)
      UserDefaults.standard.set(data, forKey: "savedWorkspaces")
    } catch {
      Task {
        await AppLogger.shared.log(
          "Failed to save workspaces: \(error)",
          level: .error,
          category: .workspace
        )
      }
    }
  }

  static func loadSSHConfigForWorkspace(_ workspace: Workspace) -> SSHServerConfiguration? {
    // If workspace has a linked server ID, load that server configuration
    if let serverID = workspace.serverID {
      return loadServerConfiguration(by: serverID)
    }

    // Fallback: try to find a server with matching host and username
    let servers = loadAllServerConfigurations()
    return servers.first { server in
      server.host == workspace.host && server.username == workspace.user
    }
  }

  static func loadServerConfiguration(by id: UUID) -> SSHServerConfiguration? {
    let servers = loadAllServerConfigurations()
    return servers.first { $0.id == id }
  }

  static func loadAllServerConfigurations() -> [SSHServerConfiguration] {
    guard let data = UserDefaults.standard.data(forKey: "savedServers") else { return [] }
    do {
      let servers = try JSONDecoder().decode([SSHServerConfiguration].self, from: data)
      return servers
    } catch {
      Task {
        await AppLogger.shared.log(
          "Failed to load server configurations: \(error)",
          level: .error,
          category: .ssh
        )
      }
      return []
    }
  }
}
