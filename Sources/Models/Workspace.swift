import Foundation

package struct Workspace: Identifiable, Codable, Equatable {
  package let id: UUID
  package var name: String
  package var host: String
  package var user: String
  package var remotePath: String
  package var tmuxSession: TmuxSessionName
  package var idleTTLMinutes: Int
  package var serverID: UUID?

  package init(
    id: UUID = UUID(),
    name: String,
    host: String,
    user: String,
    remotePath: String,
    tmuxSession: TmuxSessionName? = nil,
    idleTTLMinutes: Int = 30,
    serverID: UUID? = nil
  ) {
    self.id = id
    self.name = name
    self.host = host
    self.user = user
    self.remotePath = remotePath
    if let tmuxSession {
      self.tmuxSession = tmuxSession
    } else {
      self.tmuxSession = TmuxSessionName(workspaceName: name, path: remotePath)
    }
    self.idleTTLMinutes = idleTTLMinutes
    self.serverID = serverID
  }

  package static func generateTmuxSessionName(name: String, path: String) -> String {
    TmuxSessionName.generate(workspaceName: name, path: path)
  }
}

package enum WorkspaceOnlineState: Equatable {
  case idle
  case spawning(phase: SpawnPhase)
  case online(port: Int)
  case error(String)
}

package enum SpawnPhase: String, CaseIterable {
  case sshConnection = "SSH Connection"
  case openCodeSpawn = "OpenCode Spawn"
  case portForwarding = "SSH Port Forwarding"
  case apiHandshake = "OpenCode API"

  package var description: String {
    switch self {
    case .sshConnection:
      return "Establishing SSH connection..."
    case .openCodeSpawn:
      return "Launching OpenCode workspace services..."
    case .portForwarding:
      return "Configuring SSH port forwarding..."
    case .apiHandshake:
      return "Connecting to OpenCode server API..."
    }
  }

  package var progress: Double {
    switch self {
    case .sshConnection: return 0.25
    case .openCodeSpawn: return 0.5
    case .portForwarding: return 0.75
    case .apiHandshake: return 1.0
    }
  }
}

package struct SessionMeta: Identifiable, Codable, Equatable {
  package let id: String
  package var title: String
  package var lastMessagePreview: String
  package var updatedAt: Date
  package var workspaceId: UUID

  package init(
    id: String,
    title: String,
    lastMessagePreview: String = "",
    updatedAt: Date = Date(),
    workspaceId: UUID
  ) {
    self.id = id
    self.title = title
    self.lastMessagePreview = lastMessagePreview
    self.updatedAt = updatedAt
    self.workspaceId = workspaceId
  }
}

package struct WorkspaceDTO: Codable {
  let id: UUID
  let name: String
  let host: String
  let user: String
  let remotePath: String
  let tmuxSession: TmuxSessionName
  let idleTTLMinutes: Int
  let serverID: UUID?

  init(from workspace: Workspace) {
    self.id = workspace.id
    self.name = workspace.name
    self.host = workspace.host
    self.user = workspace.user
    self.remotePath = workspace.remotePath
    self.tmuxSession = workspace.tmuxSession
    self.idleTTLMinutes = workspace.idleTTLMinutes
    self.serverID = workspace.serverID
  }

  func toWorkspace() -> Workspace {
    Workspace(
      id: id,
      name: name,
      host: host,
      user: user,
      remotePath: remotePath,
      tmuxSession: tmuxSession,
      idleTTLMinutes: idleTTLMinutes,
      serverID: serverID
    )
  }
}

package struct SessionMetaDTO: Codable {
  let id: String
  let title: String
  let lastMessagePreview: String
  let updatedAt: Date
  let workspaceId: UUID

  init(from session: SessionMeta) {
    self.id = session.id
    self.title = session.title
    self.lastMessagePreview = session.lastMessagePreview
    self.updatedAt = session.updatedAt
    self.workspaceId = session.workspaceId
  }

  func toSessionMeta() -> SessionMeta {
    SessionMeta(
      id: id,
      title: title,
      lastMessagePreview: lastMessagePreview,
      updatedAt: updatedAt,
      workspaceId: workspaceId
    )
  }
}
