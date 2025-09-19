import Foundation

public struct TextMatch: Codable, Sendable {
  public let path: TextMatchPath
  public let lines: TextMatchLines
  public let lineNumber: Int
  public let absoluteOffset: Int
  public let submatches: [TextMatchSubmatch]

  enum CodingKeys: String, CodingKey {
    case path, lines
    case lineNumber = "line_number"
    case absoluteOffset = "absolute_offset"
    case submatches
  }
}

public struct TextMatchPath: Codable, Sendable {
  public let text: String

  public init(text: String) {
    self.text = text
  }
}

public struct TextMatchLines: Codable, Sendable {
  public let text: String

  public init(text: String) {
    self.text = text
  }
}

public struct TextMatchSubmatch: Codable, Sendable {
  public let match: TextMatchInfo
  public let start: Int
  public let end: Int
}

public struct TextMatchInfo: Codable, Sendable {
  public let text: String

  public init(text: String) {
    self.text = text
  }
}

public struct Symbol: Codable, Sendable {
  public let name: String
  public let kind: String
  public let container: String?

  public init(name: String, kind: String, container: String? = nil) {
    self.name = name
    self.kind = kind
    self.container = container
  }
}

public struct FileNode: Codable, Sendable {
  public let path: String
  public let name: String
  public let type: FileNodeType

  public init(path: String, name: String, type: FileNodeType) {
    self.path = path
    self.name = name
    self.type = type
  }
}

public enum FileNodeType: String, Codable, Sendable {
  case file
  case directory
}

public struct File: Codable, Sendable {
  public let path: String
  public let status: String

  public init(path: String, status: String) {
    self.path = path
    self.status = status
  }
}

public enum LogLevel: String, Codable, Sendable {
  case debug
  case info
  case error
  case warn
}

public struct Agent: Codable, Sendable {
  public let id: String
  public let name: String
  public let description: String?

  public init(id: String, name: String, description: String? = nil) {
    self.id = id
    self.name = name
    self.description = description
  }
}

public struct HttpToolRegistration: Codable, Sendable {
  public let name: String
  public let description: String
  public let inputSchema: [String: AnyCodable]
  public let url: String
  public let headers: [String: String]?

  enum CodingKeys: String, CodingKey {
    case name, description
    case inputSchema = "input_schema"
    case url, headers
  }
}

public struct ToolIDs: Codable, Sendable {
  public let toolIDs: [String]

  enum CodingKeys: String, CodingKey {
    case toolIDs = "tool_ids"
  }
}

public struct ToolList: Codable, Sendable {
  public let tools: [Tool]
}

public struct Tool: Codable, Sendable {
  public let name: String
  public let description: String
  public let inputSchema: [String: AnyCodable]

  enum CodingKeys: String, CodingKey {
    case name, description
    case inputSchema = "input_schema"
  }
}
