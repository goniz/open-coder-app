import Foundation

public enum ToastVariant: String, Codable, Sendable {
  case info
  case success
  case warning
  case error
}

public struct Auth: Codable, Sendable {
  public let provider: String
  public let data: [String: AnyCodable]

  public init(provider: String, data: [String: AnyCodable]) {
    self.provider = provider
    self.data = data
  }
}

public struct Event: Codable, Sendable {
  public let event: String
  public let data: String

  public init(event: String, data: String) {
    self.event = event
    self.data = data
  }
}

public struct APIErrorResponse: Codable, Sendable, LocalizedError {
  public let error: String

  public var errorDescription: String? {
    error
  }
}

// MARK: - AnyCodable Helper

public struct AnyCodable: Codable, @unchecked Sendable {
  public let value: Any

  public init(_ value: Any) {
    self.value = value
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let string = try? container.decode(String.self) {
      value = string
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map { $0.value }
    } else if let dictionary = try? container.decode([String: AnyCodable].self) {
      value = dictionary.mapValues { $0.value }
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch value {
    case let string as String:
      try container.encode(string)
    case let int as Int:
      try container.encode(int)
    case let double as Double:
      try container.encode(double)
    case let bool as Bool:
      try container.encode(bool)
    case let array as [Any]:
      try container.encode(array.map { AnyCodable($0) })
    case let dictionary as [String: Any]:
      try container.encode(dictionary.mapValues { AnyCodable($0) })
    default:
      throw EncodingError.invalidValue(
        value,
        EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode AnyCodable")
      )
    }
  }
}
