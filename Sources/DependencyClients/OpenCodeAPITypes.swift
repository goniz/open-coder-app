import Foundation

// MARK: - Model Types

public struct Project: Codable, Sendable {
  public let id: String
  public let worktree: String
  public let vcs: String
  public let time: ProjectTime

  public init(id: String, worktree: String, vcs: String, time: ProjectTime) {
    self.id = id
    self.worktree = worktree
    self.vcs = vcs
    self.time = time
  }
}

public struct ProjectTime: Codable, Sendable {
  public let created: Double
  public let initialized: Double?

  public init(created: Double, initialized: Double? = nil) {
    self.created = created
    self.initialized = initialized
  }
}

public struct Config: Codable, Sendable {
  public let schema: String?
  public let theme: String?
  public let keybinds: KeybindsConfig?
  public let tui: TUIConfig?
  public let command: [String: CommandConfig]?
  public let watcher: WatcherConfig?
  public let plugin: [String]?
  public let snapshot: Bool?
  public let share: String?
  public let autoshare: Bool?
  public let autoupdate: Bool?
  public let disabledProviders: [String]?
  public let model: String?
  public let smallModel: String?
  public let username: String?
  public let mode: ModeConfig?
  public let agents: [String: AgentConfig]?
  public let mcp: McpConfig?

  enum CodingKeys: String, CodingKey {
    case schema = "$schema"
    case theme, keybinds, tui, command, watcher, plugin, snapshot, share, autoshare, autoupdate
    case disabledProviders = "disabled_providers"
    case model, smallModel = "small_model", username, mode, agents, mcp
  }
}

public struct KeybindsConfig: Codable, Sendable {
  public let leader: String?
  public let appHelp: String?
  public let appExit: String?
  public let editorOpen: String?
  public let themeList: String?
  public let projectInit: String?
  public let toolDetails: String?
  public let thinkingBlocks: String?
  public let sessionExport: String?
  public let sessionNew: String?
  public let sessionList: String?
  public let sessionTimeline: String?
  public let sessionShare: String?
  public let sessionUnshare: String?
  public let sessionInterrupt: String?
  public let sessionCompact: String?
  public let sessionChildCycle: String?
  public let sessionChildCycleReverse: String?
  public let messagesPageUp: String?
  public let messagesPageDown: String?
  public let messagesHalfPageUp: String?
  public let messagesHalfPageDown: String?
  public let messagesFirst: String?
  public let messagesLast: String?
  public let messagesCopy: String?
  public let messagesUndo: String?
  public let messagesRedo: String?
  public let modelList: String?
  public let modelCycleRecent: String?
  public let modelCycleRecentReverse: String?
  public let agentList: String?
  public let agentCycle: String?
  public let agentCycleReverse: String?
  public let inputClear: String?
  public let inputPaste: String?
  public let inputSubmit: String?
  public let inputNewline: String?
  public let switchMode: String?
  public let switchModeReverse: String?
  public let switchAgent: String?
  public let switchAgentReverse: String?
  public let fileList: String?
  public let fileClose: String?
  public let fileSearch: String?
  public let fileDiffToggle: String?
  public let messagesPrevious: String?
  public let messagesNext: String?
  public let messagesLayoutToggle: String?
  public let messagesRevert: String?

  enum CodingKeys: String, CodingKey {
    case leader
    case appHelp = "app_help"
    case appExit = "app_exit"
    case editorOpen = "editor_open"
    case themeList = "theme_list"
    case projectInit = "project_init"
    case toolDetails = "tool_details"
    case thinkingBlocks = "thinking_blocks"
    case sessionExport = "session_export"
    case sessionNew = "session_new"
    case sessionList = "session_list"
    case sessionTimeline = "session_timeline"
    case sessionShare = "session_share"
    case sessionUnshare = "session_unshare"
    case sessionInterrupt = "session_interrupt"
    case sessionCompact = "session_compact"
    case sessionChildCycle = "session_child_cycle"
    case sessionChildCycleReverse = "session_child_cycle_reverse"
    case messagesPageUp = "messages_page_up"
    case messagesPageDown = "messages_page_down"
    case messagesHalfPageUp = "messages_half_page_up"
    case messagesHalfPageDown = "messages_half_page_down"
    case messagesFirst = "messages_first"
    case messagesLast = "messages_last"
    case messagesCopy = "messages_copy"
    case messagesUndo = "messages_undo"
    case messagesRedo = "messages_redo"
    case modelList = "model_list"
    case modelCycleRecent = "model_cycle_recent"
    case modelCycleRecentReverse = "model_cycle_recent_reverse"
    case agentList = "agent_list"
    case agentCycle = "agent_cycle"
    case agentCycleReverse = "agent_cycle_reverse"
    case inputClear = "input_clear"
    case inputPaste = "input_paste"
    case inputSubmit = "input_submit"
    case inputNewline = "input_newline"
    case switchMode = "switch_mode"
    case switchModeReverse = "switch_mode_reverse"
    case switchAgent = "switch_agent"
    case switchAgentReverse = "switch_agent_reverse"
    case fileList = "file_list"
    case fileClose = "file_close"
    case fileSearch = "file_search"
    case fileDiffToggle = "file_diff_toggle"
    case messagesPrevious = "messages_previous"
    case messagesNext = "messages_next"
    case messagesLayoutToggle = "messages_layout_toggle"
    case messagesRevert = "messages_revert"
  }
}

public struct TUIConfig: Codable, Sendable {
  public let scrollSpeed: Double?

  enum CodingKeys: String, CodingKey {
    case scrollSpeed = "scroll_speed"
  }
}

public struct CommandConfig: Codable, Sendable {
  public let template: String
  public let description: String?
  public let agent: String?
  public let model: String?
  public let subtask: Bool?
}

public struct WatcherConfig: Codable, Sendable {
  public let ignore: [String]?
}

public struct ModeConfig: Codable, Sendable {
  public let build: AgentConfig?
}

public struct AgentConfig: Codable, Sendable {
  public let model: String?
  public let temperature: Double?
  public let topP: Double?
  public let prompt: String?
  public let tools: [String: Bool]?
  public let disable: Bool?
  public let description: String?
  public let mode: String?
  public let permission: PermissionConfig?

  enum CodingKeys: String, CodingKey {
    case model, temperature, topP = "top_p", prompt, tools, disable, description, mode, permission
  }
}

public struct PermissionConfig: Codable, Sendable {
  public let edit: String?
  public let bash: StringOrObject?
  public let webfetch: String?
}

public enum StringOrObject: Codable, Sendable {
  case string(String)
  case object([String: String])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .string(string)
      return
    }
    if let object = try? container.decode([String: String].self) {
      self = .object(object)
      return
    }
    throw DecodingError.typeMismatch(
      StringOrObject.self,
      DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or [String: String]")
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let string):
      try container.encode(string)
    case .object(let object):
      try container.encode(object)
    }
  }
}

public struct McpConfig: Codable, Sendable {
  public let servers: [String: McpServerConfig]?
}

public enum McpServerConfig: Codable, Sendable {
  case local(McpLocalConfig)
  case remote(McpRemoteConfig)

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "local":
      self = .local(try McpLocalConfig(from: decoder))
    case "remote":
      self = .remote(try McpRemoteConfig(from: decoder))
    default:
      throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid MCP server type")
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .local(let config):
      try config.encode(to: encoder)
    case .remote(let config):
      try config.encode(to: encoder)
    }
  }

  enum CodingKeys: String, CodingKey {
    case type
  }
}

public struct McpLocalConfig: Codable, Sendable {
  public let type: String
  public let command: [String]
  public let environment: [String: String]?
  public let enabled: Bool?
}

public struct McpRemoteConfig: Codable, Sendable {
  public let type: String
  public let url: String
  public let enabled: Bool?
  public let headers: [String: String]?
}
