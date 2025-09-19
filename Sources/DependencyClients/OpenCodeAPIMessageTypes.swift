import Foundation

public struct Path: Codable, Sendable {
  public let path: String

  public init(path: String) {
    self.path = path
  }
}

public struct Session: Codable, Sendable {
  public let id: String
  public let title: String?
  public let parentID: String?
  public let created: Double?
  public let updated: Double?
  public let share: String?

  enum CodingKeys: String, CodingKey {
    case id, title
    case parentID = "parent_id"
    case created, updated, share
  }
}

public struct MessageWithParts: Codable, Sendable {
  public let info: Message
  public let parts: [Part]
}

public struct Message: Codable, Sendable {
  public let id: String
  public let role: String
  public let created: Double
  public let providerID: String?
  public let modelID: String?

  enum CodingKeys: String, CodingKey {
    case id, role, created
    case providerID = "provider_id"
    case modelID = "model_id"
  }
}

public struct Part: Codable, Sendable {
  public let id: String
  public let content: PartContent

  public init(id: String, content: PartContent) {
    self.id = id
    self.content = content
  }
}

public enum PartContent: Codable, Sendable {
  case text(TextPart)
  case file(FilePart)
  case agent(AgentPart)

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    if let text = try? container.decode(TextPart.self, forKey: .text) {
      self = .text(text)
      return
    }
    if let file = try? container.decode(FilePart.self, forKey: .file) {
      self = .file(file)
      return
    }
    if let agent = try? container.decode(AgentPart.self, forKey: .agent) {
      self = .agent(agent)
      return
    }

    throw DecodingError.dataCorruptedError(forKey: .text, in: container, debugDescription: "Invalid part content")
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text):
      try container.encode(text, forKey: .text)
    case .file(let file):
      try container.encode(file, forKey: .file)
    case .agent(let agent):
      try container.encode(agent, forKey: .agent)
    }
  }

  enum CodingKeys: String, CodingKey {
    case text, file, agent
  }
}

public struct TextPart: Codable, Sendable {
  public let text: String

  public init(text: String) {
    self.text = text
  }
}

public struct FilePart: Codable, Sendable {
  public let file: FileContent

  public init(file: FileContent) {
    self.file = file
  }
}

public struct AgentPart: Codable, Sendable {
  public let agent: AgentContent

  public init(agent: AgentContent) {
    self.agent = agent
  }
}

public struct FileContent: Codable, Sendable {
  public let path: String
  public let content: String?
  public let language: String?

  public init(path: String, content: String? = nil, language: String? = nil) {
    self.path = path
    self.content = content
    self.language = language
  }
}

public struct AgentContent: Codable, Sendable {
  public let name: String
  public let arguments: String?

  public init(name: String, arguments: String? = nil) {
    self.name = name
    self.arguments = arguments
  }
}

public struct AssistantMessageWithParts: Codable, Sendable {
  public let info: AssistantMessage
  public let parts: [Part]
}

public struct AssistantMessage: Codable, Sendable {
  public let id: String
  public let role: String
  public let created: Double
  public let providerID: String?
  public let modelID: String?

  enum CodingKeys: String, CodingKey {
    case id, role, created
    case providerID = "provider_id"
    case modelID = "model_id"
  }
}

public struct ModelConfig: Codable, Sendable {
  public let providerID: String
  public let modelID: String

  enum CodingKeys: String, CodingKey {
    case providerID = "provider_id"
    case modelID = "model_id"
  }
}
