import Foundation

public enum PromptPart: Codable, Sendable {
  case text(TextPartInput)
  case file(FilePartInput)
  case agent(AgentPartInput)

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    if let text = try? container.decode(TextPartInput.self, forKey: .text) {
      self = .text(text)
      return
    }
    if let file = try? container.decode(FilePartInput.self, forKey: .file) {
      self = .file(file)
      return
    }
    if let agent = try? container.decode(AgentPartInput.self, forKey: .agent) {
      self = .agent(agent)
      return
    }

    throw DecodingError.dataCorruptedError(forKey: .text, in: container, debugDescription: "Invalid prompt part")
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

public struct TextPartInput: Codable, Sendable {
  public let text: String

  public init(text: String) {
    self.text = text
  }
}

public struct FilePartInput: Codable, Sendable {
  public let file: String

  public init(file: String) {
    self.file = file
  }
}

public struct AgentPartInput: Codable, Sendable {
  public let agent: String

  public init(agent: String) {
    self.agent = agent
  }
}

public enum PermissionResponse: String, Codable, Sendable {
  case once
  case always
  case reject
}

public struct Command: Codable, Sendable {
  public let id: String
  public let name: String
  public let description: String?

  public init(id: String, name: String, description: String? = nil) {
    self.id = id
    self.name = name
    self.description = description
  }
}

public struct ProviderList: Codable, Sendable {
  public let providers: [Provider]
  public let `default`: [String: String]
}

public struct Provider: Codable, Sendable {
  public let id: String
  public let name: String
  public let models: [Model]

  public init(id: String, name: String, models: [Model]) {
    self.id = id
    self.name = name
    self.models = models
  }
}

public struct Model: Codable, Sendable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}
