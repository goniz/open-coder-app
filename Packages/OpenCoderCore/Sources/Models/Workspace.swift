import Foundation

public struct Workspace: Identifiable, Codable, Equatable, Sendable {

  public let id: UUID
  public var name: String
  public var host: String
  public var user: String
  public var remotePath: String
  public var tmuxSession: TmuxSessionName
  public var idleTTLMinutes: Int
  public var serverID: UUID?

  public init(
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

  public static func generateTmuxSessionName(name: String, path: String) -> String {
    TmuxSessionName.generate(workspaceName: name, path: path)
  }
}

public enum WorkspaceOnlineState: Equatable, Sendable {

  case idle
  case spawning(phase: SpawnPhase)
  case online(port: Int)
  case error(String)
}

public enum SpawnPhase: String, CaseIterable, Sendable {

  case sshConnection = "SSH Connection"
  case openCodeSpawn = "OpenCode Spawn"
  case portForwarding = "SSH Port Forwarding"
  case apiHandshake = "OpenCode API"

  public var description: String {
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

  public var progress: Double {
    switch self {
    case .sshConnection: return 0.25
    case .openCodeSpawn: return 0.5
    case .portForwarding: return 0.75
    case .apiHandshake: return 1.0
    }
  }
}

public struct SessionMeta: Identifiable, Codable, Equatable, Sendable {

  public let id: String
  public var title: String
  public var updatedAt: Date
  public var workspaceId: UUID

  public init(
    id: String,
    title: String,
    updatedAt: Date = Date(),
    workspaceId: UUID
  ) {
    self.id = id
    self.title = title
    self.updatedAt = updatedAt
    self.workspaceId = workspaceId
  }
}

public struct WorkspaceDTO: Codable, Sendable {

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

public struct SessionMetaDTO: Codable, Sendable {

  let id: String
  let title: String
  let updatedAt: Date
  let workspaceId: UUID

  init(from session: SessionMeta) {
    self.id = session.id
    self.title = session.title
    self.updatedAt = session.updatedAt
    self.workspaceId = session.workspaceId
  }

  func toSessionMeta() -> SessionMeta {
    SessionMeta(
      id: id,
      title: title,
      updatedAt: updatedAt,
      workspaceId: workspaceId
    )
  }
}

public struct ActivityEvent: Identifiable, Equatable, Sendable {

  public let id: UUID
  public let timestamp: Date
  public let type: EventType
  public let message: String
  public let isError: Bool

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    type: EventType,
    message: String,
    isError: Bool = false
  ) {
    self.id = id
    self.timestamp = timestamp
    self.type = type
    self.message = message
    self.isError = isError
  }

  public enum EventType: String, CaseIterable, Sendable {

    case sshConnection = "SSH Connection"
    case openCodeSpawn = "OpenCode Spawn"
    case portForwarding = "Port Forwarding"
    case apiConnection = "API Connection"
    case workspaceOnline = "Workspace Online"
    case workspaceError = "Workspace Error"

    public var icon: String {
      switch self {
      case .sshConnection: return "network"
      case .openCodeSpawn: return "terminal"
      case .portForwarding: return "arrow.triangle.branch"
      case .apiConnection: return "link"
      case .workspaceOnline: return "checkmark.circle"
      case .workspaceError: return "exclamationmark.triangle"
      }
    }

    public var colorType: AppColorType {
      switch self {
      case .sshConnection, .openCodeSpawn, .portForwarding, .apiConnection, .workspaceOnline:
        return .green
      case .workspaceError:
        return .red
      }
    }
  }

  public var formattedTimestamp: String {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    return formatter.string(from: timestamp)
  }
}
